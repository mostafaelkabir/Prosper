import Testing
import Foundation
@testable import Prosper

/// Which night a check-in is about, when it opens, and what the answers add up
/// to (E10.1). A wrong day key credits a win to the wrong night; a wrong
/// streak tells the user they lost something they didn't.
struct NightlyCheckInTests {

    private var checkInCalendar: CheckInCalendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return CheckInCalendar(calendar: calendar)
    }

    /// November 2026, Chicago time.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        checkInCalendar.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func day(_ day: Int) -> Date { date(day, 0) }

    private func key(_ day: Int) -> String { String(format: "2026-11-%02d", day) }

    private func history(_ records: [Int: CheckInOutcome]) -> CheckInHistory {
        CheckInHistory(
            records: Dictionary(uniqueKeysWithValues: records.map { (key($0.key), $0.value) }),
            calendar: checkInCalendar
        )
    }

    @Test("An answer after midnight is about the day that just ended")
    func lateNightsCountForTheDayBefore() {
        let cal = checkInCalendar
        #expect(cal.key(for: cal.day(for: date(11, 23))) == key(11))
        #expect(cal.key(for: cal.day(for: date(12, 1, 30))) == key(11))
        #expect(cal.key(for: cal.day(for: date(12, 3, 59))) == key(11))
        #expect(cal.key(for: cal.day(for: date(12, 4))) == key(12))
    }

    @Test("The check-in opens at 6 PM, or earlier with an earlier reminder")
    func opening() {
        let cal = checkInCalendar
        let ten = 22 * 60
        #expect(!cal.isOpen(at: date(11, 17, 59), reminderMinute: ten))
        #expect(cal.isOpen(at: date(11, 18), reminderMinute: ten))
        #expect(cal.isOpen(at: date(12, 2), reminderMinute: ten))
        #expect(!cal.isOpen(at: date(12, 9), reminderMinute: ten))
        #expect(cal.isOpen(at: date(11, 17), reminderMinute: 17 * 60))
    }

    @Test("A reminder after midnight belongs to the evening before it")
    func lateReminder() {
        let cal = checkInCalendar
        #expect(cal.reminderDate(for: day(11), reminderMinute: 22 * 60) == date(11, 22))
        #expect(cal.reminderDate(for: day(11), reminderMinute: 30) == date(12, 0, 30))
        #expect(cal.opensAt(day(11), reminderMinute: 30) == date(11, 18))
    }

    @Test("Reminders skip answered nights and ones already past")
    func reminderQueue() {
        let cal = checkInCalendar
        let planned = cal.reminders(from: date(11, 22, 30), reminderMinute: 22 * 60, answered: [key(13)])
        #expect(planned.count == CheckInCalendar.reminderHorizonDays - 2)
        #expect(planned.first?.key == key(12))
        #expect(planned.first?.date == date(12, 22))
        #expect(!planned.contains { $0.key == key(13) })
        // Answered before the reminder: tonight is not asked again.
        let answeredEarly = cal.reminders(from: date(11, 19), reminderMinute: 22 * 60, answered: [key(11)])
        #expect(answeredEarly.first?.key == key(12))
    }

    @Test("Tonight not answered yet doesn't break the streak")
    func pendingTonightKeepsStreak() {
        let wins = history([8: .won, 9: .won, 10: .won])
        #expect(wins.currentStreak(now: date(11, 20)) == 3)
        #expect(history([8: .won, 9: .won, 10: .won, 11: .won]).currentStreak(now: date(11, 23)) == 4)
    }

    @Test("Not today ends the streak, never the record")
    func lapseEndsStreakOnly() {
        let record = history([6: .won, 7: .won, 8: .won, 9: .notToday, 10: .won])
        #expect(record.currentStreak(now: date(11, 12)) == 1)
        #expect(record.bestStreak == 3)
        #expect(record.totalWins == 4)
        #expect(history([10: .notToday]).currentStreak(now: date(11, 12)) == 0)
    }

    @Test("A missed night breaks the streak")
    func gapBreaksStreak() {
        let record = history([7: .won, 8: .won, 10: .won])
        #expect(record.currentStreak(now: date(11, 12)) == 1)
        #expect(record.bestStreak == 2)
        #expect(history([7: .won, 8: .won]).currentStreak(now: date(11, 12)) == 0)
    }

    @Test("Best streak runs across a month boundary")
    func bestAcrossMonths() {
        let records: [String: CheckInOutcome] = ["2026-10-30": .won, "2026-10-31": .won, "2026-11-01": .won]
        #expect(CheckInHistory(records: records, calendar: checkInCalendar).bestStreak == 3)
    }

    @Test("It asks about tonight once open, else about a night that went unanswered")
    func dayToAsk() {
        let ten = 22 * 60
        let since = date(9, 12)
        let empty = history([:])
        #expect(empty.dayToAsk(now: date(11, 21), reminderMinute: ten, since: since) == day(11))
        // Daytime: yesterday went unanswered and still waits.
        #expect(empty.dayToAsk(now: date(11, 10), reminderMinute: ten, since: since) == day(10))
        // Everything answered, tonight not open yet: nothing to ask.
        #expect(history([9: .won, 10: .won]).dayToAsk(now: date(11, 10), reminderMinute: ten, since: since) == nil)
        // Tonight answered: the missed night is next.
        #expect(history([9: .won, 11: .won]).dayToAsk(now: date(11, 23), reminderMinute: ten, since: since) == day(10))
        // A night from before the check-in started is not "missed".
        #expect(empty.dayToAsk(now: date(11, 10), reminderMinute: ten, since: date(11, 9)) == nil)
    }

    @Test("A missed night waits until it is answered, however long ago")
    func missedNightsWait() {
        let ten = 22 * 60
        let since = date(1, 12)
        // Away for days: every unanswered night waits, newest first.
        let record = history([1: .won, 2: .won, 5: .notToday])
        let waiting = record.unansweredDays(now: date(8, 10), reminderMinute: ten, since: since)
        #expect(waiting == [day(7), day(6), day(4), day(3)])
        // Answering one leaves the others waiting.
        let later = history([1: .won, 2: .won, 3: .won, 4: .won, 5: .notToday, 6: .won, 7: .won])
        #expect(later.unansweredDays(now: date(8, 10), reminderMinute: ten, since: since).isEmpty)
        #expect(later.currentStreak(now: date(8, 10)) == 2)
    }

    @Test("Switching it back on doesn't count the nights it was off as missed")
    func reenablingRestartsSince() {
        let defaults = UserDefaults(suiteName: "NightlyCheckInTests.\(UUID().uuidString)")!
        let store = NightlyCheckInStore(defaults: defaults)
        defaults.set(date(1, 12), forKey: "checkIn.since")
        store.isEnabled = true // Already on: keeps its start.
        #expect(store.since == date(1, 12))
        store.isEnabled = false
        store.isEnabled = true
        #expect(store.since > date(1, 12))
    }

    @Test("The store keeps answers and defaults to 10 PM, on, asking about desire")
    func storeDefaults() {
        let defaults = UserDefaults(suiteName: "NightlyCheckInTests.\(UUID().uuidString)")!
        let store = NightlyCheckInStore(defaults: defaults)
        #expect(store.isEnabled)
        #expect(store.reminderMinute == 22 * 60)
        #expect(store.prompt == .desire)
        store.record(.won, forKey: key(11))
        store.record(.notToday, forKey: key(11))
        #expect(store.records == [key(11): .notToday])
        store.prompt = .gaze
        store.isEnabled = false
        store.clear()
        #expect(store.isEnabled)
        #expect(store.records.isEmpty)
        #expect(store.prompt == .desire)
    }
}
