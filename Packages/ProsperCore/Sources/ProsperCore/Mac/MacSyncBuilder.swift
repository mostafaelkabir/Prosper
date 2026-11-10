import Foundation

/// What the Mac publishes to the user's other devices (PLAN.md M7.2): exact
/// usage per app and site, the lock and guard state, and what the locks
/// stopped. Built from the same files the Mac's own Today view reads.
public enum MacSyncBuilder {
    /// Rows sent per day; the rest still count in the totals.
    static let topCount = 12

    public static func snapshot(deviceID: String, name: String, rules: MacRules, appVersion: String, now: Date = Date()) -> DeviceSnapshot {
        let active = rules.sessions.filter { $0.isActive(at: now) }
        let lock = active.isEmpty ? nil : LockSummary(
            startedAt: active.map(\.startedAt).min() ?? now,
            endsAt: active.map(\.endsAt).max() ?? now,
            items: items(platformIDs: active.flatMap(\.platformIDs), domains: active.flatMap(\.domains),
                         apps: active.flatMap { session in session.bundleIDs.map { session.appNames[$0] ?? $0 } })
        )
        let schedules = rules.schedules.map {
            ScheduleSummary(name: $0.name, window: "\($0.window.timeRangeText()) · \($0.window.weekdaysText)", isOnNow: $0.window.contains(now))
        }
        return DeviceSnapshot(deviceID: deviceID, name: name, platform: .mac, updatedAt: now, appVersion: appVersion,
                              guardOn: rules.guardState != nil, guardSince: rules.guardState?.enabledAt, lock: lock, schedules: schedules)
    }

    public static func day(_ usage: UsageDay, deviceID: String, settings: MacSettings, rules: MacRules, events: [MacEvent],
                           now: Date = Date(), calendar: Calendar = .current) -> DayReport {
        let summary = UsageSummary.build(days: [usage], classifier: MacClassifier(settings: settings))
        var classSeconds: [String: Double] = [:]
        for (kind, seconds) in summary.classSeconds where seconds > 0 { classSeconds[kind.rawValue] = seconds }
        if summary.unclassifiedSeconds > 0 { classSeconds["unclassified"] = summary.unclassifiedSeconds }

        let top = summary.rows.prefix(topCount).map { row -> UsageLine in
            let kind: UsageLine.Kind
            switch row.kind {
            case .app: kind = .app
            case .site: kind = .site
            case .platform: kind = .platform
            }
            return UsageLine(name: row.name, kind: kind, seconds: row.seconds, opens: row.opens, timeClass: row.timeClass?.rawValue)
        }

        let onDay = { (date: Date) in DayReport.key(for: date, calendar: calendar) == usage.day }
        let attempts = events.filter { onDay($0.at) && $0.kind != .agentStarted }.count
        let locks = rules.sessions.filter { onDay($0.startedAt) }.map {
            LockLine(startedAt: $0.startedAt, endsAt: $0.endsAt, itemCount: $0.platformIDs.count + $0.domains.count + $0.bundleIDs.count)
        }

        return DayReport(deviceID: deviceID, day: usage.day, updatedAt: now, measurement: .exact,
                         totalSeconds: usage.totalSeconds, classSeconds: classSeconds,
                         hourly: usage.hourly, hourlyDistracting: usage.hourlyDistracting, top: Array(top),
                         unlocks: usage.unlocks, opens: usage.totalOpens,
                         longestDistractingRun: usage.longestDistractingRun, longestDistractingRunName: usage.longestDistractingRunName,
                         blockedAttempts: attempts, locksStarted: locks)
    }

    /// "YouTube", "reddit.com", "Calculator": platforms by name, then sites,
    /// then apps, without repeats.
    static func items(platformIDs: [String], domains: [String], apps: [String]) -> [String] {
        var seen = Set<String>()
        let names = platformIDs.map { id in PlatformCatalog.all.first { $0.id == id }?.name ?? id } + domains + apps
        return names.filter { seen.insert($0).inserted }
    }
}
