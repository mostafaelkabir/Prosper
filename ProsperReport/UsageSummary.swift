import Foundation
import DeviceActivity
import FamilyControls
import SwiftUI

struct UsageItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var duration: TimeInterval
    var pickups: Int
    var notifications: Int = 0
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
    var apps: [UsageItem] = []
    var sites: [UsageItem] = []
    var categories: [UsageItem] = []

    var isEmpty: Bool { totalDuration == 0 && apps.isEmpty && sites.isEmpty }

    static let maxRows = 15

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
                        apps[id] = item
                        summary.totalPickups += app.numberOfPickups
                    }

                    for await site in category.webDomains {
                        let domain = site.webDomain.domain ?? "unknown"
                        var item = sites[domain] ?? UsageItem(id: domain, name: domain, duration: 0, pickups: 0)
                        item.duration += site.totalActivityDuration
                        sites[domain] = item
                    }
                }
            }
        }

        summary.days = days.map { DailyUsage(day: $0.key, duration: $0.value) }.sorted { $0.day < $1.day }
        let rankedApps = apps.values.filter { $0.duration > 0 || $0.pickups > 0 }.sorted { lhs, rhs in
            switch sortApps {
            case .time: return lhs.duration > rhs.duration
            case .opens: return lhs.pickups > rhs.pickups
            }
        }
        summary.apps = Array(rankedApps.prefix(maxRows))
        summary.sites = Array(sites.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        summary.categories = Array(categories.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        return summary
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

                        switch classification.timeClass(appToken: app.application.token, categoryToken: categoryToken) {
                        case .productive: productive += duration
                        case .distracting:
                            distracting += duration
                            let id = app.application.bundleIdentifier ?? app.application.localizedDisplayName ?? "app"
                            let name = app.application.localizedDisplayName ?? id
                            waste[id, default: UsageItem(id: id, name: name, duration: 0, pickups: 0)].duration += duration
                            waste[id]?.pickups += app.numberOfPickups
                        case .rest: rest += duration
                        case nil: break // unclassified — absorbed by subtraction
                        }
                    }

                    for await site in category.webDomains {
                        let duration = site.totalActivityDuration
                        switch classification.timeClass(domain: site.webDomain.domain) {
                        case .productive: productive += duration
                        case .distracting:
                            distracting += duration
                            let domain = site.webDomain.domain ?? "site"
                            waste[domain, default: UsageItem(id: domain, name: domain, duration: 0, pickups: 0)].duration += duration
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
        snapshot.topWaste = Array(waste.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(5))
        snapshot.hasClassification = !classification.isEmpty
        return snapshot
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

// MARK: - Sample data (simulator and previews only)

extension UsageSummary {
    static var sample: UsageSummary { sample(days: 7) }

    /// - Parameter dayCount: how many daily segments to include (1 = today only).
    static func sample(days dayCount: Int) -> UsageSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let minutes: [Double] = [142, 188, 96, 210, 167, 251, 134]
        let count = min(max(dayCount, 1), minutes.count)
        let days = (0..<count).map { offset -> DailyUsage in
            let day = calendar.date(byAdding: .day, value: offset - (count - 1), to: today) ?? today
            return DailyUsage(day: day, duration: minutes[minutes.count - count + offset] * 60)
        }
        return UsageSummary(
            totalDuration: 134 * 60,
            totalPickups: 63,
            days: days,
            apps: [
                UsageItem(id: "instagram", name: "Instagram", duration: 41 * 60, pickups: 18, notifications: 32),
                UsageItem(id: "youtube", name: "YouTube", duration: 33 * 60, pickups: 7, notifications: 9),
                UsageItem(id: "safari", name: "Safari", duration: 24 * 60, pickups: 11, notifications: 0),
                UsageItem(id: "reddit", name: "Reddit", duration: 19 * 60, pickups: 9, notifications: 14),
                UsageItem(id: "messages", name: "Messages", duration: 11 * 60, pickups: 14, notifications: 47),
                UsageItem(id: "mail", name: "Mail", duration: 6 * 60, pickups: 4, notifications: 21),
            ],
            sites: [
                UsageItem(id: "youtube.com", name: "youtube.com", duration: 14 * 60, pickups: 0),
                UsageItem(id: "reddit.com", name: "reddit.com", duration: 7 * 60, pickups: 0),
                UsageItem(id: "x.com", name: "x.com", duration: 3 * 60, pickups: 0),
            ],
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
        s.balance = TimeBalance(productive: 72 * 60, distracting: 48 * 60, rest: 20 * 60, unclassified: 34 * 60)
        s.totalPickups = 63
        s.totalNotifications = 128
        s.topWaste = [
            UsageItem(id: "instagram", name: "Instagram", duration: 26 * 60, pickups: 18),
            UsageItem(id: "youtube.com", name: "youtube.com", duration: 14 * 60, pickups: 0),
            UsageItem(id: "reddit", name: "Reddit", duration: 8 * 60, pickups: 9),
        ]
        s.hasClassification = true
        return s
    }
}
