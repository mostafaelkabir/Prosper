import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

/// `@unchecked Sendable`: every stored property is an immutable value type, but
/// ManagedSettings' opaque `Token` — which the system hands us and we only ever
/// pass along to be drawn — is not itself marked `Sendable`.
struct UsageItem: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let name: String
    var duration: TimeInterval
    var pickups: Int
    var notifications: Int = 0
    /// The system token for this app, when the row is one app. Only the report
    /// extension can obtain it, and it is what lets the row draw Apple's real
    /// app icon (the actual YouTube / Instagram logo) via `UsageIcon`.
    var appToken: ApplicationToken? = nil
    /// Same, for a website row.
    var webToken: WebDomainToken? = nil
    /// Catalog platform this row is, or belongs to — the brand fallback when
    /// there is no token to draw (websites, simulator example data).
    var platformID: String? = nil
    /// This row's time split by calendar day, oldest first. Empty for a
    /// single-day report; drives the per-row week strip and the daily average.
    var days: [DailyUsage] = []

    /// Average time per day across the days this row covers.
    func perDay(over dayCount: Int) -> TimeInterval {
        dayCount > 1 ? duration / Double(dayCount) : duration
    }
}

/// How the app list is ranked. Websites and categories always rank by time.
enum AppSort: Sendable {
    case time
    case opens
}

struct DailyUsage: Identifiable, Hashable, Sendable {
    var id: Date { day }
    let day: Date
    var duration: TimeInterval
}

struct UsageSummary: Sendable {
    var totalDuration: TimeInterval = 0
    var totalPickups: Int = 0
    var days: [DailyUsage] = []
    /// Apps and platforms merged into one ranked list — the YouTube app,
    /// `youtube.com` and `googlevideo.com` are a single "YouTube" row. This is
    /// what the "Where your time goes" list shows.
    var products: [UsageItem] = []
    var apps: [UsageItem] = []
    var sites: [UsageItem] = []
    var categories: [UsageItem] = []

    var isEmpty: Bool { totalDuration == 0 && apps.isEmpty && sites.isEmpty }

    static let maxRows = 15

    /// Number of calendar days this report covers (1 for a single-day report).
    var dayCount: Int { max(1, days.count) }

    /// Average tracked time per day over the reported range.
    var perDay: TimeInterval { totalDuration / Double(dayCount) }

    /// Walks the async result tree from the system and flattens it into totals.
    static func build(
        from data: DeviceActivityResults<DeviceActivityData>,
        sortApps: AppSort = .time
    ) async -> UsageSummary {
        var summary = UsageSummary()
        var apps: [String: UsageItem] = [:]
        var sites: [String: UsageItem] = [:]
        var categories: [String: UsageItem] = [:]
        var days: [Date: TimeInterval] = [:]
        // Per-row daily splits, kept aside so the row structs stay cheap to update.
        var appDays: [String: [Date: TimeInterval]] = [:]
        var siteDays: [String: [Date: TimeInterval]] = [:]
        let calendar = Calendar.current

        for await activity in data {
            for await segment in activity.activitySegments {
                summary.totalDuration += segment.totalActivityDuration
                summary.totalPickups += segment.totalPickupsWithoutApplicationActivity
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                days[day, default: 0] += segment.totalActivityDuration

                for await category in segment.categories {
                    let categoryName = category.category.localizedDisplayName ?? "Other"
                    categories[categoryName, default: UsageItem(id: categoryName, name: categoryName, duration: 0, pickups: 0)]
                        .duration += category.totalActivityDuration

                    for await app in category.applications {
                        let id = app.application.bundleIdentifier
                            ?? app.application.localizedDisplayName
                            ?? "unknown"
                        let name = app.application.localizedDisplayName ?? id
                        var item = apps[id] ?? UsageItem(id: id, name: name, duration: 0, pickups: 0)
                        item.duration += app.totalActivityDuration
                        item.pickups += app.numberOfPickups
                        item.notifications += app.numberOfNotifications
                        item.appToken = item.appToken ?? app.application.token
                        item.platformID = item.platformID ?? PlatformCatalog.match(name)?.id
                        apps[id] = item
                        appDays[id, default: [:]][day, default: 0] += app.totalActivityDuration
                        summary.totalPickups += app.numberOfPickups
                    }

                    for await site in category.webDomains {
                        let domain = site.webDomain.domain ?? "unknown"
                        var item = sites[domain] ?? UsageItem(id: domain, name: domain, duration: 0, pickups: 0)
                        item.duration += site.totalActivityDuration
                        item.webToken = item.webToken ?? site.webDomain.token
                        item.platformID = item.platformID ?? PlatformCatalog.match(domain)?.id
                        sites[domain] = item
                        siteDays[domain, default: [:]][day, default: 0] += site.totalActivityDuration
                    }
                }
            }
        }

        for (id, byDay) in appDays { apps[id]?.days = byDay.asDailyUsage }
        for (id, byDay) in siteDays { sites[id]?.days = byDay.asDailyUsage }

        summary.days = days.asDailyUsage
        let rankedApps = apps.values.filter { $0.duration > 0 || $0.pickups > 0 }.sorted { lhs, rhs in
            switch sortApps {
            case .time: return lhs.duration > rhs.duration
            case .opens: return lhs.pickups > rhs.pickups
            }
        }
        summary.products = rankedProducts(apps: Array(apps.values), sites: Array(sites.values))
        summary.apps = Array(rankedApps.prefix(maxRows))
        summary.sites = Array(sites.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        summary.categories = Array(categories.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        return summary
    }

    /// One ranked list of the products a person actually used: every catalog
    /// platform collapsed into a single row across its app and all its hosts,
    /// every other app and site on its own.
    ///
    /// Browser rows are scaled down by the website time iOS reports separately —
    /// that time is *inside* the browser's total, so without this, an hour of
    /// Instagram in Safari would appear twice in one list (once as "Instagram",
    /// once as "Safari"). What is left on the browser row is the browsing we
    /// could not attribute to a named site.
    static func rankedProducts(apps: [UsageItem], sites: [UsageItem]) -> [UsageItem] {
        let webTotal = sites.reduce(0) { $0 + $1.duration }
        let browserTotal = apps.filter { PlatformCatalog.isBrowser($0.name) }.reduce(0) { $0 + $1.duration }
        let browserScale = browserTotal > 0 ? max(0, browserTotal - min(webTotal, browserTotal)) / browserTotal : 1

        var buckets: [String: UsageItem] = [:]
        // Largest first, so a platform row inherits the icon of its biggest app.
        for app in apps.sorted(by: { $0.duration > $1.duration }) {
            if let platform = PlatformCatalog.match(app.name) {
                merge(app, into: &buckets, key: "platform:" + platform.id, name: platform.name, platformID: platform.id)
            } else {
                let scale = PlatformCatalog.isBrowser(app.name) ? browserScale : 1
                merge(app, into: &buckets, key: "app:" + app.id, name: app.name, platformID: nil, scale: scale)
            }
        }
        for site in sites.sorted(by: { $0.duration > $1.duration }) {
            if let platform = PlatformCatalog.match(site.name) {
                merge(site, into: &buckets, key: "platform:" + platform.id, name: platform.name, platformID: platform.id)
            } else {
                merge(site, into: &buckets, key: "site:" + site.id, name: site.name, platformID: nil)
            }
        }
        return Array(buckets.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
    }

    private static func merge(
        _ item: UsageItem,
        into buckets: inout [String: UsageItem],
        key: String,
        name: String,
        platformID: String?,
        scale: Double = 1
    ) {
        var bucket = buckets[key] ?? UsageItem(id: key, name: name, duration: 0, pickups: 0)
        bucket.duration += item.duration * scale
        bucket.pickups += item.pickups
        bucket.notifications += item.notifications
        bucket.appToken = bucket.appToken ?? item.appToken
        bucket.webToken = bucket.webToken ?? item.webToken
        bucket.platformID = bucket.platformID ?? platformID
        var byDay = Dictionary(uniqueKeysWithValues: bucket.days.map { ($0.day, $0.duration) })
        for day in item.days { byDay[day.day, default: 0] += day.duration * scale }
        bucket.days = byDay.asDailyUsage
        buckets[key] = bucket
    }
}

extension Dictionary where Key == Date, Value == TimeInterval {
    /// Day buckets as a chronological series.
    var asDailyUsage: [DailyUsage] {
        map { DailyUsage(day: $0.key, duration: $0.value) }.sorted { $0.day < $1.day }
    }
}

struct TotalTime: Sendable {
    var duration: TimeInterval = 0
    var pickups: Int = 0
}

// MARK: - Today snapshot (classified balance + reflex counts)

/// Everything the waste-first Today hero needs: a real four-class balance built
/// from the user's labels, the phone-pickup and notification counts, and the
/// ranked list of *where* the distracting time actually went.
struct TodaySnapshot: Sendable {
    var balance = TimeBalance()
    var totalPickups: Int = 0
    var totalNotifications: Int = 0
    /// Distracting apps and sites, largest first — answers "wasted where?".
    var topWaste: [UsageItem] = []
    /// True when the user has classified nothing, so we show a "label your apps"
    /// nudge instead of a ring that is 100% unclassified.
    var hasClassification: Bool = false

    var isEmpty: Bool { balance.total == 0 }

    /// Walks the system result tree once, assigning each app (by token) and each
    /// website (by domain) to a time class. Unclassified is derived by
    /// subtraction so the ring always sums to the real tracked total — nothing is
    /// assumed productive (UX-9). Web-domain time is a subset of the browser
    /// app's time, so if labels overlap we scale the labelled parts down to fit
    /// the total rather than double-count.
    static func build(
        from data: DeviceActivityResults<DeviceActivityData>,
        classification: SharedClassification.Snapshot
    ) async -> TodaySnapshot {
        var total: TimeInterval = 0
        var productive: TimeInterval = 0
        var distracting: TimeInterval = 0
        var rest: TimeInterval = 0
        var pickups = 0
        var notifications = 0
        var waste: [String: UsageItem] = [:]

        for await activity in data {
            for await segment in activity.activitySegments {
                total += segment.totalActivityDuration
                pickups += segment.totalPickupsWithoutApplicationActivity

                for await category in segment.categories {
                    let categoryToken = category.category.token

                    for await app in category.applications {
                        let duration = app.totalActivityDuration
                        pickups += app.numberOfPickups
                        notifications += app.numberOfNotifications
                        let appName = app.application.localizedDisplayName

                        switch classification.timeClass(appToken: app.application.token, categoryToken: categoryToken, appName: appName) {
                        case .productive: productive += duration
                        case .distracting:
                            distracting += duration
                            // Cluster the waste line under the platform when the app
                            // belongs to one, so "YouTube" is one row (app + sites).
                            let fallbackID = app.application.bundleIdentifier ?? appName ?? "app"
                            let bucket = Self.wasteBucket(for: appName, fallbackID: fallbackID, fallbackName: appName ?? fallbackID)
                            var item = waste[bucket.key] ?? UsageItem(id: bucket.key, name: bucket.name, duration: 0, pickups: 0)
                            item.duration += duration
                            item.pickups += app.numberOfPickups
                            item.appToken = item.appToken ?? app.application.token
                            item.platformID = item.platformID ?? bucket.platformID
                            waste[bucket.key] = item
                        case .rest: rest += duration
                        case nil: break // unclassified — absorbed by subtraction
                        }
                    }

                    for await site in category.webDomains {
                        let duration = site.totalActivityDuration
                        let host = site.webDomain.domain
                        switch classification.timeClass(domain: host) {
                        case .productive: productive += duration
                        case .distracting:
                            distracting += duration
                            let bucket = Self.wasteBucket(for: host, fallbackID: host ?? "site", fallbackName: host ?? "site")
                            var item = waste[bucket.key] ?? UsageItem(id: bucket.key, name: bucket.name, duration: 0, pickups: 0)
                            item.duration += duration
                            item.webToken = item.webToken ?? site.webDomain.token
                            item.platformID = item.platformID ?? bucket.platformID
                            waste[bucket.key] = item
                        case .rest: rest += duration
                        case nil: break
                        }
                    }
                }
            }
        }

        // Guard against app+domain overlap pushing labelled time past the real
        // total: scale the three labelled classes to fit, leaving unclassified ≥ 0.
        let labelled = productive + distracting + rest
        if labelled > total, labelled > 0 {
            let k = total / labelled
            productive *= k; distracting *= k; rest *= k
        }
        let unclassified = max(0, total - (productive + distracting + rest))

        var snapshot = TodaySnapshot()
        snapshot.balance = TimeBalance(productive: productive, distracting: distracting, rest: rest, unclassified: unclassified)
        snapshot.totalPickups = pickups
        snapshot.totalNotifications = notifications
        // Top 3 only: the hero is a glance, and the full ranked list lives in
        // Insights → What. Keeping it short also bounds the hero's height so the
        // (non-self-sizing) report fits the host frame without clipping.
        snapshot.topWaste = Array(waste.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(3))
        // "Classified" if the user labelled anything OR the catalog's built-in
        // defaults placed real time into a class (UX-20) — so the "everything is
        // unclassified" nudge doesn't show once known apps are auto-classified.
        snapshot.hasClassification = !classification.isEmpty || (productive + distracting + rest) > 0
        return snapshot
    }

    /// Where a distracting app or site is filed in the "Where it went" list: under
    /// its platform when it belongs to one (so the YouTube app, `youtube.com` and
    /// `googlevideo.com` collapse into a single "YouTube" row), else on its own.
    static func wasteBucket(for text: String?, fallbackID: String, fallbackName: String) -> (key: String, name: String, platformID: String?) {
        if let platform = PlatformCatalog.match(text) {
            return ("platform:" + platform.id, platform.name, platform.id)
        }
        return (fallbackID, fallbackName, nil)
    }
}

extension TimeInterval {
    /// "2h 14m", "14m", or "<1m".
    var usageFormatted: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return self > 0 ? "<1m" : "0m"
    }
}

// MARK: - Sample data
//
// Fabricated numbers, compiled ONLY for the simulator, which has no Screen Time
// to read. A shipped user must never see invented figures presented as their own
// usage, so this is a compile-time guarantee rather than a rule to remember: on
// any device build — debug or release — these declarations do not exist, and a
// call site that forgets its #if fails to build instead of shipping (REL-11).
#if targetEnvironment(simulator)

extension UsageSummary {
    static var sample: UsageSummary { sample(days: 7) }

    /// - Parameter dayCount: how many daily segments to include (1 = today only).
    static func sample(days dayCount: Int) -> UsageSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let minutes: [Double] = [142, 188, 96, 210, 167, 251, 134]
        let count = min(max(dayCount, 1), minutes.count)
        let dayDates = (0..<count).map { offset in
            calendar.date(byAdding: .day, value: offset - (count - 1), to: today) ?? today
        }
        let days = dayDates.enumerated().map { index, day in
            DailyUsage(day: day, duration: minutes[minutes.count - count + index] * 60)
        }
        // Per-row daily shapes, so the week strip on each row is plausible rather
        // than flat. Values are fractions of the row's total.
        let shapes: [[Double]] = [
            [0.9, 1.4, 0.6, 1.3, 1.0, 1.5, 0.8],
            [1.2, 0.7, 1.1, 0.9, 1.4, 0.6, 1.1],
            [0.6, 1.0, 1.3, 0.8, 1.1, 1.2, 1.0],
        ]
        func spread(_ total: TimeInterval, _ shapeIndex: Int) -> [DailyUsage] {
            guard count > 1 else { return [DailyUsage(day: today, duration: total)] }
            let shape = Array(shapes[shapeIndex % shapes.count].suffix(count))
            let sum = shape.reduce(0, +)
            return zip(dayDates, shape).map { DailyUsage(day: $0, duration: total * $1 / sum) }
        }

        var apps = [
            UsageItem(id: "instagram", name: "Instagram", duration: 41 * 60, pickups: 18, notifications: 32),
            UsageItem(id: "youtube", name: "YouTube", duration: 33 * 60, pickups: 7, notifications: 9),
            UsageItem(id: "safari", name: "Safari", duration: 24 * 60, pickups: 11, notifications: 0),
            UsageItem(id: "reddit", name: "Reddit", duration: 19 * 60, pickups: 9, notifications: 14),
            UsageItem(id: "messages", name: "Messages", duration: 11 * 60, pickups: 14, notifications: 47),
            UsageItem(id: "mail", name: "Mail", duration: 6 * 60, pickups: 4, notifications: 21),
        ]
        var sites = [
            UsageItem(id: "youtube.com", name: "youtube.com", duration: 14 * 60, pickups: 0),
            UsageItem(id: "reddit.com", name: "reddit.com", duration: 7 * 60, pickups: 0),
            UsageItem(id: "x.com", name: "x.com", duration: 3 * 60, pickups: 0),
        ]
        for index in apps.indices { apps[index].days = spread(apps[index].duration, index) }
        for index in sites.indices { sites[index].days = spread(sites[index].duration, index + 1) }

        return UsageSummary(
            totalDuration: 134 * 60,
            totalPickups: 63,
            days: days,
            products: rankedProducts(apps: apps, sites: sites),
            apps: apps,
            sites: sites,
            categories: [
                UsageItem(id: "Social", name: "Social", duration: 60 * 60, pickups: 0),
                UsageItem(id: "Entertainment", name: "Entertainment", duration: 33 * 60, pickups: 0),
                UsageItem(id: "Productivity & Finance", name: "Productivity & Finance", duration: 17 * 60, pickups: 0),
            ]
        )
    }
}

extension TotalTime {
    static var sample: TotalTime {
        TotalTime(duration: 134 * 60, pickups: 63)
    }
}

extension TodaySnapshot {
    static var sample: TodaySnapshot {
        var s = TodaySnapshot()
        // Totals match UsageSummary.sample / TotalTime.sample (134m, 63 pickups)
        // so Today, Insights and the When grid tell one consistent story (QA-4).
        s.balance = TimeBalance(productive: 54 * 60, distracting: 40 * 60, rest: 16 * 60, unclassified: 24 * 60)
        s.totalPickups = 63
        s.totalNotifications = 128
        s.topWaste = [ // sums to the 40m distracting total
            UsageItem(id: "instagram", name: "Instagram", duration: 20 * 60, pickups: 18, platformID: "instagram"),
            UsageItem(id: "youtube", name: "YouTube", duration: 12 * 60, pickups: 0, platformID: "youtube"),
            UsageItem(id: "reddit", name: "Reddit", duration: 8 * 60, pickups: 9, platformID: "reddit"),
        ]
        s.hasClassification = true
        return s
    }
}
#endif
