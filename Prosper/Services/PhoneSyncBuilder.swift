import Foundation

/// What this iPhone tells the user's Mac (PLAN.md M7.3): the lock and guard,
/// schedules, warnings, and the waste-list markers. Never per-app minutes:
/// iOS keeps those inside the report extension. Takes plain values so it is
/// tested without SwiftData or Screen Time.
enum PhoneSyncBuilder {
    struct Session {
        var startedAt: Date
        var endsAt: Date
        var domains: [String]
        var appCount: Int
    }

    struct Schedule {
        var name: String
        var startMinute: Int
        var endMinute: Int
        var weekdays: Set<Int>
        var isOnNow: Bool
    }

    struct Warning {
        var level: Int
        var text: String
        var at: Date
    }

    static func snapshot(deviceID: String, sessions: [Session], schedules: [Schedule], guardSince: Date?,
                         measuresWaste: Bool, appVersion: String, now: Date = .now) -> DeviceSnapshot {
        let running = sessions.filter { $0.startedAt <= now && now < $0.endsAt }
        let lock = running.isEmpty ? nil : LockSummary(
            startedAt: running.map(\.startedAt).min() ?? now,
            endsAt: running.map(\.endsAt).max() ?? now,
            items: items(running)
        )
        return DeviceSnapshot(
            deviceID: deviceID, name: "iPhone", platform: .iPhone, updatedAt: now, appVersion: appVersion,
            guardOn: guardSince != nil, guardSince: guardSince, lock: lock,
            schedules: schedules.map { ScheduleSummary(name: $0.name, window: windowText($0), isOnNow: $0.isOnNow) },
            measuresWaste: measuresWaste
        )
    }

    static func day(_ key: String, deviceID: String, marks: [WasteMark], sessions: [Session], warnings: [Warning],
                    now: Date = .now, calendar: Calendar = .current) -> DayReport {
        let onDay = { (date: Date) in DayReport.key(for: date, calendar: calendar) == key }
        return DayReport(
            deviceID: deviceID, day: key, updatedAt: now, measurement: .wasteMarkers,
            wasteMarks: marks,
            warnings: warnings.filter { onDay($0.at) }.map { WarningLine(level: $0.level, text: $0.text, at: $0.at) },
            locksStarted: sessions.filter { onDay($0.startedAt) }.map {
                LockLine(startedAt: $0.startedAt, endsAt: $0.endsAt, itemCount: $0.domains.count + $0.appCount)
            }
        )
    }

    /// "reddit.com, youtube.com, 3 apps".
    static func items(_ sessions: [Session]) -> [String] {
        var seen = Set<String>()
        let domains = sessions.flatMap(\.domains).filter { seen.insert($0).inserted }
        let apps = sessions.map(\.appCount).reduce(0, +)
        return domains + (apps > 0 ? ["\(apps) app\(apps == 1 ? "" : "s")"] : [])
    }

    /// "10:00 PM – 7:00 AM · Every day"
    static func windowText(_ schedule: Schedule, calendar: Calendar = .current) -> String {
        func time(_ minute: Int) -> String {
            let date = calendar.date(from: DateComponents(hour: minute / 60, minute: minute % 60)) ?? .now
            return date.formatted(date: .omitted, time: .shortened)
        }
        let days: String
        switch schedule.weekdays {
        case Set(1...7): days = "Every day"
        case Set(2...6): days = "Weekdays"
        case [1, 7]: days = "Weekends"
        default: days = schedule.weekdays.sorted().map { calendar.shortWeekdaySymbols[($0 - 1) % 7] }.joined(separator: ", ")
        }
        return "\(time(schedule.startMinute)) – \(time(schedule.endMinute)) · \(days)"
    }
}
