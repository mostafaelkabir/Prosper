import Foundation

/// The nightly check-in (E10.1): one private question before sleep, answered
/// with "I won" or "Not today", and the winning streak it builds.
///
/// The question never names the habit. It shows up in a notification on the
/// lock screen and on the Today screen, and both are places someone else might
/// glance at. The user knows what they are answering; nobody else needs to.
///
/// A lapse ends the streak, never the record: the best streak and the total
/// number of wins stay on screen. Shame is what keeps the loop going (E10
/// brief), so a "Not today" is noted and the copy moves on to tomorrow.
enum CheckInOutcome: String, Codable, Sendable {
    case won
    case notToday
}

/// The ways the question can be put. The user picks one; the default is the
/// one that names the struggle without naming the habit.
struct CheckInPrompt: Identifiable, Hashable, Sendable {
    let id: String
    /// The question up to the day, e.g. "Did you win against your desire".
    let stem: String

    /// Tonight's question.
    var question: String { question(when: "today") }

    /// The question about a missed night: "yesterday", "on Monday".
    func question(when: String) -> String { "\(stem) \(when)?" }

    static let desire = CheckInPrompt(id: "desire", stem: "Did you win against your desire")
    static let discipline = CheckInPrompt(id: "discipline", stem: "Were you disciplined")
    static let gaze = CheckInPrompt(id: "gaze", stem: "Did you guard your gaze")

    static let all = [desire, discipline, gaze]

    static func with(id: String) -> CheckInPrompt {
        all.first { $0.id == id } ?? desire
    }
}

/// Which day a check-in is about, and when it can be answered.
///
/// A day's check-in opens in the evening and stays open past midnight: an
/// answer at 1 AM is about the day that just ended, not the one that has
/// barely started. Built from wall-clock hours on each day, like
/// `ScheduledLock.window`, so daylight-saving days still open at 6 PM.
struct CheckInCalendar: Sendable {
    /// Answers before this hour count for the day before.
    static let rolloverHour = 4
    /// The latest a day's check-in opens. An earlier reminder opens it earlier.
    static let opensHour = 18
    /// How many days of reminders are queued ahead. Each launch, foreground
    /// and answer tops the queue up again.
    static let reminderHorizonDays = 14

    var calendar: Calendar = .current

    /// The day being reflected on at `date`.
    func day(for date: Date) -> Date {
        let shifted = date.addingTimeInterval(-Double(Self.rolloverHour) * 3600)
        return calendar.startOfDay(for: shifted)
    }

    /// A stable key for a day, in the user's calendar: "2026-11-11".
    func key(for day: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// When the reminder for `day` fires. A reminder set after midnight but
    /// before the rollover belongs to the evening before it.
    func reminderDate(for day: Date, reminderMinute: Int) -> Date? {
        let afterMidnight = reminderMinute < Self.rolloverHour * 60
        guard let date = calendar.date(byAdding: .day, value: afterMidnight ? 1 : 0, to: day) else { return nil }
        return calendar.date(bySettingHour: reminderMinute / 60, minute: reminderMinute % 60, second: 0, of: date)
    }

    /// When `day`'s check-in can first be answered: 6 PM, or the reminder if
    /// that comes earlier.
    func opensAt(_ day: Date, reminderMinute: Int) -> Date? {
        guard let evening = calendar.date(bySettingHour: Self.opensHour, minute: 0, second: 0, of: day) else { return nil }
        guard let reminder = reminderDate(for: day, reminderMinute: reminderMinute) else { return evening }
        return min(evening, reminder)
    }

    func isOpen(at date: Date, reminderMinute: Int) -> Bool {
        guard let opens = opensAt(day(for: date), reminderMinute: reminderMinute) else { return false }
        return date >= opens
    }

    /// The reminders to queue from `now`: one per day for the horizon, minus
    /// days already answered and reminders already past.
    func reminders(from now: Date, reminderMinute: Int, answered: Set<String>) -> [(key: String, date: Date)] {
        let today = day(for: now)
        return (0..<Self.reminderHorizonDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let date = reminderDate(for: day, reminderMinute: reminderMinute),
                  date > now else { return nil }
            let key = key(for: day)
            return answered.contains(key) ? nil : (key, date)
        }
    }
}

/// The check-in's settings and answers, in the App Group so a widget or the
/// Mac can read them later. Local only; "Delete my data" clears it.
struct NightlyCheckInStore {
    let defaults: UserDefaults

    static var appGroup: NightlyCheckInStore? {
        UserDefaults(suiteName: PersistenceConfig.appGroupID).map { NightlyCheckInStore(defaults: $0) }
    }

    static let defaultReminderMinute = 22 * 60

    private enum Key {
        static let enabled = "checkIn.enabled"
        static let reminderMinute = "checkIn.reminderMinute"
        static let promptID = "checkIn.promptID"
        static let records = "checkIn.records"
        static let since = "checkIn.since"
    }

    /// On unless the user switched it off: asking every night at 10 PM is the
    /// feature.
    var isEnabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        nonmutating set {
            // Nights while it was off were never asked, so they must not wait
            // for an answer once it is back on.
            if newValue && !isEnabled { defaults.set(Date.now, forKey: Key.since) }
            defaults.set(newValue, forKey: Key.enabled)
        }
    }

    /// Minutes after midnight.
    var reminderMinute: Int {
        get { defaults.object(forKey: Key.reminderMinute) as? Int ?? Self.defaultReminderMinute }
        nonmutating set { defaults.set(min(max(newValue, 0), 24 * 60 - 1), forKey: Key.reminderMinute) }
    }

    var prompt: CheckInPrompt {
        get { CheckInPrompt.with(id: defaults.string(forKey: Key.promptID) ?? CheckInPrompt.desire.id) }
        nonmutating set { defaults.set(newValue.id, forKey: Key.promptID) }
    }

    /// Answers by day key.
    var records: [String: CheckInOutcome] {
        guard let raw = defaults.dictionary(forKey: Key.records) as? [String: String] else { return [:] }
        return raw.compactMapValues(CheckInOutcome.init(rawValue:))
    }

    /// When the check-in started asking: first seen on this install, or last
    /// switched back on. A night before this is not "missed"; it was never
    /// asked.
    var since: Date {
        if let date = defaults.object(forKey: Key.since) as? Date { return date }
        let now = Date.now
        defaults.set(now, forKey: Key.since)
        return now
    }

    func record(_ outcome: CheckInOutcome, forKey key: String) {
        var raw = (defaults.dictionary(forKey: Key.records) as? [String: String]) ?? [:]
        raw[key] = outcome.rawValue
        defaults.set(raw, forKey: Key.records)
    }

    func clear() {
        for key in [Key.enabled, Key.reminderMinute, Key.promptID, Key.records, Key.since] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// What the answers add up to. Pure, so the streak rules are tested directly.
struct CheckInHistory: Sendable {
    let records: [String: CheckInOutcome]
    var calendar = CheckInCalendar()

    /// Consecutive wins counting back from today. An unanswered today does not
    /// break the streak, so it starts from yesterday until tonight is answered.
    func currentStreak(now: Date) -> Int {
        let cal = calendar.calendar
        var day = calendar.day(for: now)
        if records[calendar.key(for: day)] == nil {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while records[calendar.key(for: day)] == .won {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The longest run of consecutive wins ever recorded.
    var bestStreak: Int {
        let days = records.filter { $0.value == .won }.keys.compactMap(date(fromKey:)).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    var totalWins: Int { records.values.filter { $0 == .won }.count }

    func outcome(on day: Date) -> CheckInOutcome? { records[calendar.key(for: day)] }

    /// Every night still waiting for an answer, newest first: tonight once it
    /// is open, then each earlier night that went unanswered. A missed night
    /// waits until it is answered; nights from before the check-in was
    /// switched on (`since`) were never asked, so they are not waiting.
    func unansweredDays(now: Date, reminderMinute: Int, since: Date) -> [Date] {
        let cal = calendar.calendar
        let today = calendar.day(for: now)
        var days: [Date] = []
        if calendar.isOpen(at: now, reminderMinute: reminderMinute), outcome(on: today) == nil {
            days.append(today)
        }
        // Bounded so a clock set years back cannot spin here.
        var day = today
        for _ in 0..<366 {
            guard let previous = cal.date(byAdding: .day, value: -1, to: day),
                  let opened = calendar.opensAt(previous, reminderMinute: reminderMinute),
                  since <= opened else { break }
            day = previous
            if outcome(on: day) == nil { days.append(day) }
        }
        return days
    }

    /// The night the check-in should ask about now, if any.
    func dayToAsk(now: Date, reminderMinute: Int, since: Date) -> Date? {
        unansweredDays(now: now, reminderMinute: reminderMinute, since: since).first
    }

    /// The last seven days, oldest first, ending today.
    func lastSevenDays(now: Date) -> [Date] {
        let today = calendar.day(for: now)
        return (-6...0).compactMap { calendar.calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
