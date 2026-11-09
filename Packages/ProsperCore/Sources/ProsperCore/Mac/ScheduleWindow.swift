import Foundation

/// When a schedule is on: wall-clock minutes and the weekdays a window starts
/// on. Same rules as the iPhone's `ScheduledLock` (E3.6): an end at or before
/// the start runs past midnight, and Friday's bedtime window still runs into
/// Saturday morning.
public struct ScheduleWindow: Codable, Equatable, Hashable, Sendable {
    /// Minutes after midnight.
    public var startMinute: Int
    public var endMinute: Int
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>

    public init(startMinute: Int, endMinute: Int, weekdays: Set<Int> = Set(1...7)) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdays = weekdays
    }

    public var crossesMidnight: Bool { endMinute <= startMinute }

    public var spanMinutes: Int {
        crossesMidnight ? endMinute + 24 * 60 - startMinute : endMinute - startMinute
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        interval(containing: date, calendar: calendar) != nil
    }

    /// The window that contains `date`, or nil when the schedule is off then.
    /// Built from wall-clock hour and minute on each candidate day, so a
    /// daylight-saving day still opens at 10:00 PM.
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
                  let endDay = calendar.date(byAdding: .day, value: crossesMidnight ? 1 : 0, to: day),
                  let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: endDay),
                  start < end else { continue }
            if date >= start && date < end { return DateInterval(start: start, end: end) }
        }
        return nil
    }

    /// "10:00 PM – 7:00 AM"
    public func timeRangeText(calendar: Calendar = .current) -> String {
        func text(_ minute: Int) -> String {
            var components = DateComponents()
            components.hour = minute / 60
            components.minute = minute % 60
            let date = calendar.date(from: components) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }
        return "\(text(startMinute)) – \(text(endMinute))"
    }

    /// "Every day", "Weekdays", "Weekends" or "Mon, Wed".
    public var weekdaysText: String {
        if weekdays.count == 7 { return "Every day" }
        if weekdays == Set(2...6) { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { symbols[($0 - 1) % 7] }.joined(separator: ", ")
    }
}
