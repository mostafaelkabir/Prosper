import Testing
import Foundation
@testable import Prosper

/// When a scheduled lock is on, and what the service refuses (E3.6). A wrong
/// window either locks at the wrong hour or lets a schedule be edited while it
/// is running — the way out the product promises does not exist.
struct ScheduledLockTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// 2026-11-06 is a Friday (weekday 6).
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func lock(start: Int, end: Int, days: Set<Int> = Set(1...7), domains: [String] = ["reddit.com"]) -> ScheduledLock {
        ScheduledLock(name: "Test", startMinute: start, endMinute: end, weekdays: days, selectionData: nil, domains: domains)
    }

    @Test("A daytime window is on inside it and off either side, end exclusive")
    func daytimeWindow() {
        let work = lock(start: 9 * 60, end: 17 * 60)
        #expect(work.window(containing: date(6, 8, 59), calendar: calendar) == nil)
        #expect(work.window(containing: date(6, 9), calendar: calendar)?.end == date(6, 17))
        #expect(work.window(containing: date(6, 16, 59), calendar: calendar) != nil)
        #expect(work.window(containing: date(6, 17), calendar: calendar) == nil)
    }

    @Test("Bedtime runs past midnight into the next morning")
    func overnightWindow() {
        let bedtime = lock(start: 22 * 60, end: 7 * 60)
        #expect(bedtime.crossesMidnight)
        #expect(bedtime.spanMinutes == 9 * 60)
        #expect(bedtime.window(containing: date(6, 21, 59), calendar: calendar) == nil)
        #expect(bedtime.window(containing: date(6, 23), calendar: calendar)?.end == date(7, 7))
        #expect(bedtime.window(containing: date(7, 3), calendar: calendar)?.start == date(6, 22))
        #expect(bedtime.window(containing: date(7, 7), calendar: calendar) == nil)
    }

    @Test("Days count from when the window opens")
    func weekdaysFollowTheStart() {
        // Weekdays only: Friday night runs into Saturday, Saturday night does not start.
        let weeknights = lock(start: 22 * 60, end: 7 * 60, days: Set(2...6))
        #expect(weeknights.window(containing: date(7, 3), calendar: calendar) != nil)
        #expect(weeknights.window(containing: date(7, 23), calendar: calendar) == nil)
        let work = lock(start: 9 * 60, end: 17 * 60, days: Set(2...6))
        #expect(work.window(containing: date(7, 10), calendar: calendar) == nil)
    }

    @Test("Validation refuses what iOS can't run or what locks nothing")
    func validation() {
        #expect(ScheduledLockService.validate(lock(start: 9 * 60, end: 9 * 60 + 14)) == .tooShort)
        #expect(ScheduledLockService.validate(lock(start: 9 * 60, end: 9 * 60 + 15)) == nil)
        #expect(ScheduledLockService.validate(lock(start: 23 * 60 + 50, end: 4)) == .tooShort)
        #expect(ScheduledLockService.validate(lock(start: 9 * 60, end: 17 * 60, days: [])) == .noDays)
        #expect(ScheduledLockService.validate(lock(start: 9 * 60, end: 17 * 60, domains: [])) == .nothingSelected)
    }

    @Test("Templates match what they say")
    func templates() {
        let bedtime = ScheduledLock.make(.bedtime, selectionData: nil, domains: ["x.com"])
        #expect(bedtime.timeRangeText.isEmpty == false)
        #expect(bedtime.weekdays == Set(1...7) && bedtime.crossesMidnight)
        let work = ScheduledLock.make(.workFocus, selectionData: nil, domains: ["x.com"])
        #expect(work.daysText == "Weekdays" && !work.crossesMidnight)
        #expect(ScheduledLockService.validate(bedtime) == nil)
        #expect(ScheduledLockService.validate(work) == nil)
    }
}
