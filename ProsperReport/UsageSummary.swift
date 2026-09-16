import Foundation
import DeviceActivity
import SwiftUI

struct UsageItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var duration: TimeInterval
    var pickups: Int
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
    static func build(from data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
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
        summary.apps = Array(apps.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        summary.sites = Array(sites.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        summary.categories = Array(categories.values.filter { $0.duration > 0 }.sorted { $0.duration > $1.duration }.prefix(maxRows))
        return summary
    }
}

struct TotalTime: Sendable {
    var duration: TimeInterval = 0
    var pickups: Int = 0
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
                UsageItem(id: "instagram", name: "Instagram", duration: 41 * 60, pickups: 18),
                UsageItem(id: "youtube", name: "YouTube", duration: 33 * 60, pickups: 7),
                UsageItem(id: "safari", name: "Safari", duration: 24 * 60, pickups: 11),
                UsageItem(id: "reddit", name: "Reddit", duration: 19 * 60, pickups: 9),
                UsageItem(id: "messages", name: "Messages", duration: 11 * 60, pickups: 14),
                UsageItem(id: "mail", name: "Mail", duration: 6 * 60, pickups: 4),
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
