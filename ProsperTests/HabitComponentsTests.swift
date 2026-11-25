import Testing
import Foundation
@testable import Prosper

/// The numbers behind the lock dial, the day bar and "locks next" (UX-30).
/// A dial that lands off its range starts a lock of a length nobody chose, and
/// a bar that fills the wrong hours shows a schedule that is not the one saved.
struct HabitComponentsTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// 2026-11-06 is a Friday (weekday 6).
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func lock(start: Int, end: Int, days: Set<Int> = Set(1...7)) -> ScheduledLock {
        ScheduledLock(name: "Test", startMinute: start, endMinute: end, weekdays: days, selectionData: nil, domains: ["reddit.com"])
    }

    // MARK: Lock length

    @Test("The dial snaps to five minutes and never leaves its range")
    func snapping() {
        #expect(LockLength.snapped(62, min: 15, max: 240) == 60)
        #expect(LockLength.snapped(63, min: 15, max: 240) == 65)
        #expect(LockLength.snapped(3, min: 15, max: 240) == 15)
        #expect(LockLength.snapped(900, min: 15, max: 240) == 240)
        // The longest lock is 23h 55m; a full day must come back inside it.
        #expect(LockLength.snapped(24 * 60, min: 15, max: 23 * 60 + 55) == 23 * 60 + 55)
    }

    @Test("Marks run from the shortest lock to the cap, both included")
    func marks() {
        let firstLock = LockLength.marks(min: 15, max: 240)
        #expect(firstLock.first == 15)
        #expect(firstLock.last == 240)
        #expect(firstLock.count == 46)
        #expect(LockLength.marks(min: 15, max: 23 * 60 + 55).last == 23 * 60 + 55)
        #expect(LockLength.marks(min: 30, max: 15).isEmpty)
    }

    @Test("Lengths read the same on the dial and out loud")
    func wording() {
        #expect(LockLength.text(minutes: 45) == "45m")
        #expect(LockLength.text(minutes: 120) == "2h")
        #expect(LockLength.text(minutes: 95) == "1h 35m")
        #expect(LockLength.spoken(minutes: 60) == "1 hour")
        #expect(LockLength.spoken(minutes: 95) == "1 hour 35 minutes")
        #expect(LockLength.spoken(minutes: 15) == "15 minutes")
        #expect(LockLength.minutes(3600) == 60)
    }

    @Test("An end time past midnight carries its day")
    func endText() {
        let evening = date(6, 22)
        let sameDay = LockLength.endText(after: 3600, from: evening, calendar: calendar)
        let nextDay = LockLength.endText(after: 4 * 3600, from: evening, calendar: calendar)
        // The same clock time is longer once the day is added to it.
        #expect(nextDay.count > sameDay.count)
    }

    // MARK: Day bar

    @Test("A daytime window is one stretch of the day")
    func daytimeBand() {
        let pieces = DaySpan.segments(start: 9 * 60, end: 17 * 60)
        #expect(pieces.count == 1)
        #expect(pieces[0].lowerBound == 9.0 / 24)
        #expect(pieces[0].upperBound == 17.0 / 24)
    }

    @Test("An overnight window wraps: morning, then night")
    func overnightBand() {
        let pieces = DaySpan.segments(start: 22 * 60, end: 7 * 60)
        #expect(pieces.count == 2)
        #expect(pieces[0] == 0...(7.0 / 24))
        #expect(pieces[1] == (22.0 / 24)...1)
    }

    @Test("A window ending at midnight has no empty morning piece")
    func endsAtMidnight() {
        let pieces = DaySpan.segments(start: 20 * 60, end: 0)
        #expect(pieces.count == 1)
        #expect(pieces[0] == (20.0 / 24)...1)
    }

    @Test("The now marker sits where the clock is")
    func nowFraction() {
        #expect(DaySpan.fraction(of: date(6, 12), calendar: calendar) == 0.5)
        #expect(DaySpan.fraction(of: date(6, 0), calendar: calendar) == 0)
        #expect(DaySpan.fraction(of: date(6, 18), calendar: calendar) == 0.75)
    }

    // MARK: Locks next

    @Test("The next start is today when the window has not opened yet")
    func nextStartToday() {
        let bedtime = lock(start: 22 * 60, end: 7 * 60)
        #expect(bedtime.nextStart(after: date(6, 9), calendar: calendar) == date(6, 22))
    }

    @Test("Once today's window has opened, the next start is the next chosen day")
    func nextStartSkipsToChosenDay() {
        // Weekdays only, asked on Friday evening: Monday morning.
        let work = lock(start: 9 * 60, end: 17 * 60, days: Set(2...6))
        #expect(work.nextStart(after: date(6, 18), calendar: calendar) == date(9, 9))
    }

    @Test("A schedule with no days never starts")
    func nextStartNoDays() {
        #expect(lock(start: 9 * 60, end: 17 * 60, days: []).nextStart(after: date(6, 9), calendar: calendar) == nil)
    }

    @Test("Night schedules get the moon, daytime ones the clock")
    func symbols() {
        #expect(lock(start: 22 * 60, end: 7 * 60).symbol == "moon.fill")
        #expect(lock(start: 9 * 60, end: 17 * 60).symbol == "clock.fill")
    }
}
