import Foundation
import Testing
@testable import ProsperCore

/// The two promises: a lock is never shortened or ended early, and the guard
/// is never shrunk or switched off (CLAUDE.md, PLAN.md §7).
struct RulesBookTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func started(_ minutes: Int = 60) throws -> (MacRules, MacLockSession) {
        try RulesBook.startingSession(.empty, minutes: minutes, domains: ["https://www.YouTube.com/watch"], bundleIDs: ["com.tinyspeck.slackmacgap"], platformIDs: ["reddit"], now: now)
    }

    @Test("Starting a lock normalises sites and sets the end")
    func start() throws {
        let (rules, session) = try started()
        #expect(session.domains == ["youtube.com"])
        #expect(session.endsAt == now.addingTimeInterval(3600))
        #expect(rules.sessions.count == 1)
        #expect(rules.revision == 1)
    }

    @Test("A lock with nothing in it, or shorter than a minute, is refused")
    func refuses() {
        #expect(throws: RulesBook.EditError.nothingToLock) { try RulesBook.startingSession(.empty, minutes: 10, domains: ["not a domain"], bundleIDs: [], platformIDs: [], now: now) }
        #expect(throws: RulesBook.EditError.tooShort) { try RulesBook.startingSession(.empty, minutes: 0, domains: ["x.com"], bundleIDs: [], platformIDs: [], now: now) }
    }

    @Test("Every operation preserves what was locked before it")
    func everyOperationPreserves() throws {
        let (base, session) = try started()
        let guarded = RulesBook.enablingGuard(base, now: now)
        let (withSchedule, schedule) = try RulesBook.addingSchedule(guarded, name: "Night", window: ScheduleWindow(startMinute: 0, endMinute: 24 * 60 - 1), domains: ["tiktok.com"], bundleIDs: [], platformIDs: [], now: now)
        let operations: [(String, MacRules)] = [
            ("add to session", try RulesBook.adding(to: session.id, withSchedule, domains: ["x.com"], now: now)),
            ("extend", try RulesBook.extending(session.id, withSchedule, byMinutes: 5, now: now)),
            ("add schedule", try RulesBook.addingSchedule(withSchedule, name: "B", window: ScheduleWindow(startMinute: 60, endMinute: 120), domains: ["a.com"], bundleIDs: [], platformIDs: [], now: now).0),
            ("add to schedule", try RulesBook.adding(toSchedule: schedule.id, withSchedule, domains: ["b.com"])),
            ("enable guard again", RulesBook.enablingGuard(withSchedule, now: now.addingTimeInterval(99))),
            ("add to guard", RulesBook.addingToGuard(withSchedule, domains: ["c.com"], bundleIDs: ["com.x"])),
        ]
        for (name, next) in operations {
            #expect(withSchedule.isPreserved(by: next, at: now), "\(name) lost something")
        }
    }

    @Test("Extending never makes a lock shorter")
    func extendOnlyLonger() throws {
        let (rules, session) = try started()
        #expect(throws: RulesBook.EditError.tooShort) { try RulesBook.extending(session.id, rules, byMinutes: -30, now: now) }
    }

    @Test("A schedule cannot be removed while its window is open")
    func scheduleRemoval() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let (rules, schedule) = try RulesBook.addingSchedule(.empty, name: "All day", window: ScheduleWindow(startMinute: 0, endMinute: 23 * 60 + 59), domains: ["x.com"], bundleIDs: [], platformIDs: [], now: now)
        #expect(throws: RulesBook.EditError.self) { try RulesBook.removingSchedule(schedule.id, rules, now: now, calendar: cal) }
        let hour = cal.component(.hour, from: now)
        let later = ScheduleWindow(startMinute: ((hour + 2) % 24) * 60, endMinute: ((hour + 3) % 24) * 60)
        let (rules2, closed) = try RulesBook.addingSchedule(.empty, name: "Later", window: later, domains: ["x.com"], bundleIDs: [], platformIDs: [], now: now)
        let removed = try RulesBook.removingSchedule(closed.id, rules2, now: now, calendar: cal)
        #expect(removed.schedules.isEmpty)
        #expect(removed.merged(with: rules2, at: now, calendar: cal).schedules.isEmpty)
    }

    @Test("Hand-editing the file to drop a lock or the guard is undone by the merge")
    func tamperIsUndone() throws {
        let (base, session) = try started()
        let kept = RulesBook.addingToGuard(RulesBook.enablingGuard(base, now: now), domains: ["extra.com"])
        var tampered = kept
        tampered.sessions = []
        tampered.guardState = nil
        let merged = tampered.merged(with: kept, at: now)
        #expect(merged.sessions.map(\.id) == [session.id])
        #expect(merged.guardState?.extraDomains == ["extra.com"])

        var shortened = kept
        shortened.sessions[0].endsAt = now.addingTimeInterval(60)
        shortened.guardState?.safeSearch = false
        let merged2 = shortened.merged(with: kept, at: now)
        #expect(merged2.sessions[0].endsAt == now.addingTimeInterval(3600))
        #expect(merged2.guardState?.safeSearch == true)
        #expect(kept.isPreserved(by: merged2, at: now))
        #expect(!kept.isPreserved(by: shortened, at: now))
    }

    @Test("A removal tombstone is refused while the schedule is open")
    func tombstoneRefusedWhileOpen() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let (rules, schedule) = try RulesBook.addingSchedule(.empty, name: "All day", window: ScheduleWindow(startMinute: 0, endMinute: 23 * 60 + 59), domains: ["x.com"], bundleIDs: [], platformIDs: [], now: now)
        var forged = rules
        forged.schedules = []
        forged.removedScheduleIDs = [schedule.id]
        let merged = forged.merged(with: rules, at: now, calendar: cal)
        #expect(merged.schedules.map(\.id) == [schedule.id])
    }

    @Test("Expired sessions leave the document, and only then")
    func expiry() throws {
        let (rules, _) = try started(10)
        #expect(rules.merged(with: .empty, at: now.addingTimeInterval(599)).sessions.count == 1)
        #expect(rules.merged(with: .empty, at: now.addingTimeInterval(600)).sessions.isEmpty)
    }

    @Test("The guard API has no way to switch it off")
    func guardHasNoOff() {
        // RulesBook's guard operations are enable (idempotent) and add. Neither
        // takes anything away; this test fails to compile if someone adds a
        // parameter that could.
        let on = RulesBook.enablingGuard(.empty, now: now)
        let again = RulesBook.enablingGuard(on, now: now.addingTimeInterval(1000))
        #expect(again.guardState?.enabledAt == now)
        let added = RulesBook.addingToGuard(on, domains: [])
        #expect(added.guardState == on.guardState)
    }
}
