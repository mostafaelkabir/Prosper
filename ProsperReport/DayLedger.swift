import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
// DeviceActivityResults only exists where DeviceActivity meets SwiftUI.
import SwiftUI

/// One walk over the system's result tree, with every app and website given
/// the label the user chose for it. The Today hero and the day ledger are both
/// built from this, so their numbers cannot drift apart.
struct ClassifiedDay {
    var total: TimeInterval = 0
    var pickups = 0
    var notifications = 0
    var apps: [TodaySnapshot.ClassifiedUsage] = []
    var sites: [TodaySnapshot.ClassifiedUsage] = []
    var userHasLabels = false

    static func walk(
        _ data: DeviceActivityResults<DeviceActivityData>,
        classification: SharedClassification.Snapshot
    ) async -> ClassifiedDay {
        var day = ClassifiedDay()
        day.userHasLabels = !classification.isEmpty

        for await activity in data {
            for await segment in activity.activitySegments {
                day.total += segment.totalActivityDuration
                day.pickups += segment.totalPickupsWithoutApplicationActivity

                for await category in segment.categories {
                    let categoryToken = category.category.token

                    for await app in category.applications {
                        day.pickups += app.numberOfPickups
                        day.notifications += app.numberOfNotifications
                        let appName = app.application.localizedDisplayName
                        day.apps.append(TodaySnapshot.ClassifiedUsage(
                            id: app.application.bundleIdentifier ?? appName ?? "app",
                            name: appName,
                            duration: app.totalActivityDuration,
                            pickups: app.numberOfPickups,
                            timeClass: classification.timeClass(appToken: app.application.token, categoryToken: categoryToken, appName: appName),
                            appToken: app.application.token
                        ))
                    }

                    for await site in category.webDomains {
                        let host = site.webDomain.domain
                        day.sites.append(TodaySnapshot.ClassifiedUsage(
                            id: host ?? "site",
                            name: host,
                            duration: site.totalActivityDuration,
                            timeClass: classification.timeClass(domain: host),
                            webToken: site.webDomain.token
                        ))
                    }
                }
            }
        }
        return day
    }
}

/// Where the hours went, filed under the label each app and site carries
/// (UX-29): what is not labelled yet first, because that is the part the
/// person can still do something about, then Distracting, Productive, Rest.
///
/// `@unchecked Sendable` for the same reason as `UsageItem`: the rows carry
/// the system's opaque tokens, which are only ever passed along to be drawn.
struct DayLedger: @unchecked Sendable {
    struct Group: Identifiable {
        let timeClass: TimeClass
        /// The class's share of the day. Always the same number the Today
        /// ring shows for it.
        var total: TimeInterval
        var rows: [UsageItem]
        /// Rows past `maxRows`, as a count and their time together.
        var hiddenCount = 0
        var hiddenDuration: TimeInterval = 0
        var id: TimeClass { timeClass }
    }

    var balance = TimeBalance()
    /// In reading order; a class with no time is left out.
    var groups: [Group] = []

    var isEmpty: Bool { balance.total == 0 }

    static let maxRows = 20
    static let order: [TimeClass] = [.unclassified, .distracting, .productive, .rest]

    /// Files every app and site under its label.
    ///
    /// The totals are `TodaySnapshot.assemble`'s, so this screen and the Today
    /// ring agree to the minute. The rows follow the same browser rule: a
    /// website's time is already inside the browser's, so it is taken out of
    /// the browser before the browser is listed. One addition, because this
    /// list is where sites get labelled: browsing on a site with no label is
    /// shown as its own row whenever the browser has no label either, so the
    /// site can be seen and labelled. When the browser does carry a label,
    /// that browsing stays in the browser's row, as it does in the ring.
    static func assemble(_ day: ClassifiedDay) -> DayLedger {
        let snapshot = TodaySnapshot.assemble(
            total: day.total,
            pickups: day.pickups,
            notifications: day.notifications,
            apps: day.apps,
            sites: day.sites,
            userHasLabels: day.userHasLabels
        )

        let labelledSiteTime = day.sites.filter { $0.timeClass != nil }.reduce(0) { $0 + $1.duration }
        let unlabelledSiteTime = day.sites.filter { $0.timeClass == nil }.reduce(0) { $0 + $1.duration }
        let browsers = day.apps.filter { PlatformCatalog.isBrowser($0.name) }
        let browserTime = browsers.reduce(0) { $0 + $1.duration }
        let unlabelledBrowserTime = browsers.filter { $0.timeClass == nil }.reduce(0) { $0 + $1.duration }

        // A labelled browser keeps everything except labelled sites (the ring's rule).
        let labelledBrowserScale = browserTime > 0 ? (browserTime - min(labelledSiteTime, browserTime)) / browserTime : 1
        // An unlabelled browser also gives up the unlabelled sites listed beside it.
        let unlabelledBrowserScale = browserTime > 0
            ? (browserTime - min(labelledSiteTime + unlabelledSiteTime, browserTime)) / browserTime
            : 1
        // The part of unlabelled browsing that happened in unlabelled browsers.
        let unlabelledSiteScale = browserTime > 0 ? unlabelledBrowserTime / browserTime : 1

        var buckets: [TimeClass: [String: UsageItem]] = [:]

        func add(_ usage: TodaySnapshot.ClassifiedUsage, duration: TimeInterval) {
            guard duration > 0 else { return }
            let timeClass = TimeClass(usage.timeClass)
            let bucket = TodaySnapshot.wasteBucket(for: usage.name, fallbackID: usage.id, fallbackName: usage.name ?? usage.id)
            var item = buckets[timeClass]?[bucket.key] ?? UsageItem(id: bucket.key, name: bucket.name, duration: 0, pickups: 0)
            item.duration += duration
            item.pickups += usage.pickups
            item.appToken = item.appToken ?? usage.appToken
            item.webToken = item.webToken ?? usage.webToken
            item.platformID = item.platformID ?? bucket.platformID
            buckets[timeClass, default: [:]][bucket.key] = item
        }

        for site in day.sites {
            add(site, duration: site.timeClass == nil ? site.duration * unlabelledSiteScale : site.duration)
        }
        // Largest first, so a platform row carries the icon of its biggest app.
        for app in day.apps.sorted(by: { $0.duration > $1.duration }) {
            guard PlatformCatalog.isBrowser(app.name) else {
                add(app, duration: app.duration)
                continue
            }
            add(app, duration: app.duration * (app.timeClass == nil ? unlabelledBrowserScale : labelledBrowserScale))
        }

        var ledger = DayLedger()
        ledger.balance = snapshot.balance
        for timeClass in order {
            let total = snapshot.balance.value(timeClass)
            var rows = (buckets[timeClass] ?? [:]).values.filter { $0.duration >= 1 }.sorted {
                $0.duration != $1.duration ? $0.duration > $1.duration : $0.name < $1.name
            }
            // The rows never claim more than the class holds: the same safety
            // net the balance applies when Screen Time's numbers overlap.
            let listed = rows.reduce(0) { $0 + $1.duration }
            if listed > total, listed > 0 {
                for index in rows.indices { rows[index].duration *= total / listed }
            }
            guard total >= 1 || !rows.isEmpty else { continue }
            var group = Group(timeClass: timeClass, total: total, rows: Array(rows.prefix(maxRows)))
            if rows.count > maxRows {
                let hidden = rows.dropFirst(maxRows)
                group.hiddenCount = hidden.count
                group.hiddenDuration = hidden.reduce(0) { $0 + $1.duration }
            }
            ledger.groups.append(group)
        }
        return ledger
    }
}

extension TimeClass {
    /// The class a label maps to; no label is Unclassified.
    init(_ kind: SharedClassification.ClassKind?) {
        switch kind {
        case .productive: self = .productive
        case .distracting: self = .distracting
        case .rest: self = .rest
        case nil: self = .unclassified
        }
    }
}

// MARK: - Sample data (simulator only, see UsageSummary.swift)

#if targetEnvironment(simulator)
extension DayLedger {
    /// The example day from `UsageSummary.sample`, filed under whatever labels
    /// are saved right now, through the real `assemble`. Changing a label in
    /// the simulator moves the example row, as it would on a phone.
    static func sample(days dayCount: Int, classification: SharedClassification.Snapshot = SharedClassification.load()) -> DayLedger {
        let summary = UsageSummary.sample(days: 1)
        let scale = Double(max(1, dayCount))
        var day = ClassifiedDay()
        day.total = summary.totalDuration * scale
        day.pickups = summary.totalPickups
        day.userHasLabels = !classification.isEmpty
        day.apps = summary.apps.map { app in
            TodaySnapshot.ClassifiedUsage(
                id: app.id, name: app.name, duration: app.duration * scale, pickups: app.pickups,
                timeClass: classification.timeClass(appToken: nil, categoryToken: nil, appName: app.name)
            )
        }
        day.sites = summary.sites.map { site in
            TodaySnapshot.ClassifiedUsage(
                id: site.id, name: site.name, duration: site.duration * scale,
                timeClass: classification.timeClass(domain: site.name)
            )
        }
        return assemble(day)
    }
}
#endif
