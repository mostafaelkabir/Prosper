import Foundation

/// One day of Mac usage, as measured by the agent (PLAN.md §3.6). Seconds are
/// exact: the agent sees every app switch, idle stretch and screen lock, so
/// these numbers are the Mac's own, not an estimate.
///
/// Site time is time a browser was frontmost on that site, so it is contained
/// in the browser's app time; summaries subtract it so nothing counts twice.
public struct UsageDay: Codable, Equatable, Sendable {
    /// "yyyy-MM-dd" in the Mac's time zone.
    public var day: String
    public var apps: [String: AppUsage]
    public var sites: [String: SiteUsage]
    /// Active seconds per hour of the day, 24 entries.
    public var hourly: [Double]
    /// Distracting seconds per hour (apps and sites classed distracting).
    public var hourlyDistracting: [Double]
    /// Screen unlocks: the Mac's "pickups".
    public var unlocks: Int
    /// First active moment of the day.
    public var firstActive: Date?
    /// Longest unbroken stretch on one distracting app or site, in seconds.
    public var longestDistractingRun: Double
    public var longestDistractingRunName: String?

    public init(day: String) {
        self.day = day
        apps = [:]
        sites = [:]
        hourly = Array(repeating: 0, count: 24)
        hourlyDistracting = Array(repeating: 0, count: 24)
        unlocks = 0
        firstActive = nil
        longestDistractingRun = 0
        longestDistractingRunName = nil
    }

    public var totalSeconds: Double { apps.values.reduce(0) { $0 + $1.seconds } }
    public var totalOpens: Int { apps.values.reduce(0) { $0 + $1.opens } }
    public var distractingSeconds: Double { hourlyDistracting.reduce(0, +) }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public struct AppUsage: Codable, Equatable, Sendable {
    public var name: String
    public var seconds: Double
    /// Times the app came to the front.
    public var opens: Int
    public var isBrowser: Bool
    /// `LSApplicationCategoryType`, used for automatic classification.
    public var category: String?

    public init(name: String, seconds: Double = 0, opens: Int = 0, isBrowser: Bool = false, category: String? = nil) {
        self.name = name
        self.seconds = seconds
        self.opens = opens
        self.isBrowser = isBrowser
        self.category = category
    }
}

public struct SiteUsage: Codable, Equatable, Sendable {
    public var seconds: Double
    public var visits: Int

    public init(seconds: Double = 0, visits: Int = 0) {
        self.seconds = seconds
        self.visits = visits
    }
}

// MARK: - Recording

public extension UsageDay {
    /// Books `seconds` of active time that ended at `end` against an app and,
    /// when a browser was on a site, that site. Splits across hour boundaries.
    mutating func record(
        bundleID: String,
        app: AppUsage,
        site: String?,
        from start: Date,
        to end: Date,
        timeClass: TimeClassKind?,
        calendar: Calendar = .current
    ) {
        guard end > start else { return }
        let seconds = end.timeIntervalSince(start)
        var entry = apps[bundleID] ?? AppUsage(name: app.name, isBrowser: app.isBrowser, category: app.category)
        entry.name = app.name
        entry.seconds += seconds
        apps[bundleID] = entry
        if let site {
            var s = sites[site] ?? SiteUsage()
            s.seconds += seconds
            sites[site] = s
        }
        if firstActive == nil || start < firstActive! { firstActive = start }

        var cursor = start
        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
            let hourEnd = min(end, hourStart.addingTimeInterval(3600))
            let slice = hourEnd.timeIntervalSince(cursor)
            hourly[hour] += slice
            if timeClass == .distracting { hourlyDistracting[hour] += slice }
            guard hourEnd > cursor else { break }
            cursor = hourEnd
        }
    }

    mutating func recordOpen(bundleID: String, app: AppUsage) {
        var entry = apps[bundleID] ?? AppUsage(name: app.name, isBrowser: app.isBrowser, category: app.category)
        entry.opens += 1
        apps[bundleID] = entry
    }

    mutating func recordVisit(site: String) {
        var s = sites[site] ?? SiteUsage()
        s.visits += 1
        sites[site] = s
    }
}
