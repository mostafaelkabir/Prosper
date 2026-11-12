import Testing
import Foundation
@testable import Prosper

/// When new apps can be installed and when the rule can be changed (E9.6). A
/// wrong window opens the App Store at the weak moment it exists to close; a
/// wrong Friday makes the rule a setting like any other.
struct InstallWindowTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// 2026-11-13 is a Friday (weekday 6).
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test("Installs are allowed inside the window only, end exclusive")
    func morningWindow() {
        let rule = InstallWindowRule.standard
        #expect(InstallGate.deniesInstalls(rule: rule, at: date(11, 6, 59), calendar: calendar))
        #expect(!InstallGate.deniesInstalls(rule: rule, at: date(11, 7), calendar: calendar))
        #expect(!InstallGate.deniesInstalls(rule: rule, at: date(11, 7, 59), calendar: calendar))
        #expect(InstallGate.deniesInstalls(rule: rule, at: date(11, 8), calendar: calendar))
        #expect(InstallGate.deniesInstalls(rule: rule, at: date(11, 23), calendar: calendar))
    }

    @Test("No rule means the gate is open")
    func off() {
        #expect(!InstallGate.deniesInstalls(rule: nil, at: date(11, 3), calendar: calendar))
    }

    @Test("A window can run past midnight")
    func overnightWindow() {
        let rule = InstallWindowRule(startMinute: 23 * 60 + 30, lengthMinutes: 60)
        #expect(rule.endMinute == 30)
        #expect(!InstallGate.deniesInstalls(rule: rule, at: date(12, 0, 15), calendar: calendar))
        #expect(InstallGate.deniesInstalls(rule: rule, at: date(12, 0, 30), calendar: calendar))
        #expect(rule.window(containing: date(11, 23, 45), calendar: calendar)?.end == date(12, 0, 30))
    }

    @Test("The next opening is later today or tomorrow")
    func nextOpening() {
        let rule = InstallWindowRule.standard
        #expect(rule.nextOpening(after: date(11, 5), calendar: calendar) == date(11, 7))
        #expect(rule.nextOpening(after: date(11, 7), calendar: calendar) == date(12, 7))
        #expect(rule.nextOpening(after: date(11, 9), calendar: calendar) == date(12, 7))
    }

    @Test("Changes are possible only Friday 11 AM to 1 PM")
    func changeWindow() {
        let friday = DateInterval(start: date(13, 11), end: date(13, 13))
        #expect(InstallChangeWindow.availability(now: date(11, 12), lastChangeAt: nil, calendar: calendar) == .closed(next: friday))
        #expect(InstallChangeWindow.availability(now: date(13, 10, 59), lastChangeAt: nil, calendar: calendar) == .closed(next: friday))
        #expect(InstallChangeWindow.availability(now: date(13, 11), lastChangeAt: nil, calendar: calendar) == .open(until: date(13, 13)))
        let nextFriday = DateInterval(start: date(20, 11), end: date(20, 13))
        #expect(InstallChangeWindow.availability(now: date(13, 13), lastChangeAt: nil, calendar: calendar) == .closed(next: nextFriday))
    }

    @Test("One change per Friday; last week's change doesn't count")
    func oncePerFriday() {
        let nextFriday = DateInterval(start: date(20, 11), end: date(20, 13))
        #expect(InstallChangeWindow.availability(now: date(13, 12), lastChangeAt: date(13, 11, 20), calendar: calendar) == .used(next: nextFriday))
        #expect(InstallChangeWindow.availability(now: date(13, 12), lastChangeAt: date(6, 11, 20), calendar: calendar) == .open(until: date(13, 13)))
    }

    @Test("Outside Friday the service refuses to change or switch off")
    func serviceRefusesOutsideFriday() throws {
        let defaults = UserDefaults(suiteName: "InstallWindowTests.\(UUID().uuidString)")!
        let state = InstallWindowState(defaults: defaults)
        state.save(.standard)
        let service = InstallWindowService(state: state)
        // The service reads the device calendar; noon on a Wednesday is
        // outside the Friday window in every time zone.
        let wednesday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
        #expect(throws: InstallWindowService.ChangeError.self) {
            try service.turnOff(now: wednesday)
        }
        #expect(throws: InstallWindowService.ChangeError.self) {
            try service.change(to: InstallWindowRule(startMinute: 22 * 60, lengthMinutes: 120), now: wednesday)
        }
        #expect(state.rule == .standard)
        #expect(state.lastChangeAt == nil)
    }

    @Test("Switching on twice is refused, so 'on' can't be used to rewrite the window")
    func turnOnOnlyWhenOff() throws {
        let defaults = UserDefaults(suiteName: "InstallWindowTests.\(UUID().uuidString)")!
        let state = InstallWindowState(defaults: defaults)
        state.save(.standard)
        let service = InstallWindowService(state: state)
        #expect(throws: InstallWindowService.ChangeError.alreadyOn) {
            try service.turnOn(InstallWindowRule(startMinute: 0, lengthMinutes: 120))
        }
        #expect(state.rule == .standard)
    }
}
