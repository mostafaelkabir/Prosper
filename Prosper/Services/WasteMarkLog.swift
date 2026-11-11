import DeviceActivity
import Foundation

/// Silent markers on today's waste-list time (M7.3). iOS shows per-app
/// minutes only inside the report extension, which cannot send anything, so
/// this is how the iPhone tells the Mac how much it was used: the waste
/// monitor carries an event at every 15 minutes (half-hours after 4 hours),
/// and ProsperMonitor writes down when each one was reached. The highest
/// marker is a floor ("at least 1h 15m"), and when it was reached says when
/// the time went. No notification: warnings stay the three-rung ladder.
enum WasteMarkLog {
    static let eventPrefix = "prosper.waste.mark."

    /// 15-minute steps to 4h, then half-hours to 8h: 24 events.
    static let minutes: [Int] = Array(stride(from: 15, through: 240, by: 15)) + Array(stride(from: 270, through: 480, by: 30))

    static func eventName(_ minutes: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name(eventPrefix + String(minutes))
    }

    static func minutes(for event: DeviceActivityEvent.Name) -> Int? {
        guard event.rawValue.hasPrefix(eventPrefix) else { return nil }
        return Int(event.rawValue.dropFirst(eventPrefix.count))
    }

    private static let key = "wasteMarks"
    /// Days kept: today and two before, enough to publish yesterday's.
    private static let keepDays = 3

    static var appGroup: UserDefaults? { UserDefaults(suiteName: PersistenceConfig.appGroupID) }

    /// Notes that today's waste time reached `minutes`. The first time a
    /// marker is reached counts; a monitor reinstalled mid-day re-delivers
    /// markers it already passed, and those keep their original time.
    static func record(minutes: Int, at date: Date = .now, defaults: UserDefaults? = appGroup, calendar: Calendar = .current) {
        guard let defaults else { return }
        var all = load(defaults)
        let day = DayReport.key(for: date, calendar: calendar)
        var marks = all[day] ?? [:]
        if marks[String(minutes)] == nil { marks[String(minutes)] = date }
        all[day] = marks
        for old in all.keys.sorted().dropLast(keepDays) { all[old] = nil }
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }

    static func marks(day: String, defaults: UserDefaults? = appGroup) -> [WasteMark] {
        guard let defaults else { return [] }
        return (load(defaults)[day] ?? [:])
            .compactMap { minutes, at in Int(minutes).map { WasteMark(minutes: $0, reachedAt: at) } }
            .sorted { $0.minutes < $1.minutes }
    }

    private static func load(_ defaults: UserDefaults) -> [String: [String: Date]] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: Date]].self, from: data)) ?? [:]
    }
}
