import Foundation
import DeviceActivity
import ManagedSettings

/// The install window (E9.6): new apps can only be installed during a short
/// daily window, and the window itself can only be changed on Friday, around
/// Jumu'ah.
///
/// Harmful apps are usually looked for at a weak moment: late, alone, bored.
/// The window moves that decision to a time chosen with a clear head, and the
/// weekly change window keeps the weak moment from simply moving the window.
///
/// Shared by the app, which saves the rule, and ProsperMonitor, which opens
/// and closes the gate when iOS wakes it. Kept to Foundation, DeviceActivity
/// and ManagedSettings so the monitor can compile it.
///
/// Rules:
///
/// 1. **Its own store.** The gate lives in `ManagedSettingsStore(named:
///    "installWindow")`, so no block session, schedule or the guard can open
///    it, and it cannot touch theirs.
/// 2. **Derived, never remembered.** Whether installs are allowed is worked
///    out from the saved rule and the clock every time (`InstallGate.reconcile`),
///    by the app on launch and foreground and by the monitor on every wake-up.
///    A dropped or early callback heals itself on the next one.
/// 3. **Loosening only on Friday.** Changing the window or switching it off is
///    possible only inside the weekly change window, once per Friday. Switching
///    it on is possible any time, because it only ever makes things stricter.
struct InstallWindowRule: Codable, Equatable, Sendable {
    /// Minutes after midnight.
    var startMinute: Int
    var lengthMinutes: Int

    static let lengths = [30, 60, 120]
    static let standard = InstallWindowRule(startMinute: 7 * 60, lengthMinutes: 60)

    var endMinute: Int { (startMinute + lengthMinutes) % (24 * 60) }

    /// The window that contains `date`, or nil when installs are closed then.
    /// Built from wall-clock hours like `ScheduledLock.window`, including a
    /// window that runs past midnight.
    func window(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day) else { continue }
            let end = start.addingTimeInterval(TimeInterval(lengthMinutes * 60))
            if date >= start && date < end { return DateInterval(start: start, end: end) }
        }
        return nil
    }

    /// The next time the window opens after `date`.
    func nextOpening(after date: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
                  start > date else { continue }
            return start
        }
        return nil
    }

    /// The daily interval that wakes ProsperMonitor as the window opens and
    /// closes.
    var deviceActivitySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: startMinute / 60, minute: startMinute % 60),
            intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60),
            repeats: true
        )
    }
}

/// The weekly moment the install window can be changed: Friday, 11 AM to 1 PM,
/// around Jumu'ah. Fixed on purpose: a change window the user could move would
/// be one more thing to move at the wrong moment.
enum InstallChangeWindow {
    /// Calendar weekday, 1 = Sunday.
    static let weekday = 6
    static let startMinute = 11 * 60
    static let lengthMinutes = 120

    /// What the user can do to the rule right now.
    enum Availability: Equatable {
        /// Inside the change window and not yet used this Friday.
        case open(until: Date)
        /// Inside the change window, but this Friday's change is spent.
        case used(next: DateInterval)
        /// Outside the change window.
        case closed(next: DateInterval)
    }

    static func window(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard calendar.component(.weekday, from: date) == weekday,
              let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: date) else { return nil }
        let window = DateInterval(start: start, duration: TimeInterval(lengthMinutes * 60))
        return date >= window.start && date < window.end ? window : nil
    }

    /// The next change window that opens after `date`.
    static func next(after date: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  calendar.component(.weekday, from: day) == weekday,
                  let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
                  start > date else { continue }
            return DateInterval(start: start, duration: TimeInterval(lengthMinutes * 60))
        }
        return nil
    }

    static func availability(now: Date, lastChangeAt: Date?, calendar: Calendar = .current) -> Availability {
        let upcoming = next(after: now, calendar: calendar) ?? DateInterval(start: now, duration: 0)
        guard let current = window(containing: now, calendar: calendar) else { return .closed(next: upcoming) }
        if let lastChangeAt, current.contains(lastChangeAt) { return .used(next: upcoming) }
        return .open(until: current.end)
    }
}

/// The install window's record in the App Group. A nil rule means it is off.
struct InstallWindowState {
    let defaults: UserDefaults

    /// Must match `PersistenceConfig.appGroupID`. Duplicated so the monitor
    /// does not depend on which other files it compiles.
    static let appGroupID = "group.com.mostafa.prosper"

    static var appGroup: InstallWindowState? {
        UserDefaults(suiteName: appGroupID).map { InstallWindowState(defaults: $0) }
    }

    private enum Key {
        static let rule = "installWindow.rule"
        static let lastChangeAt = "installWindow.lastChangeAt"
    }

    var rule: InstallWindowRule? {
        guard let data = defaults.data(forKey: Key.rule) else { return nil }
        return try? JSONDecoder().decode(InstallWindowRule.self, from: data)
    }

    /// When the rule was last changed or switched off, to allow one change per
    /// Friday.
    var lastChangeAt: Date? { defaults.object(forKey: Key.lastChangeAt) as? Date }

    func save(_ rule: InstallWindowRule) {
        guard let data = try? JSONEncoder().encode(rule) else { return }
        defaults.set(data, forKey: Key.rule)
    }

    func removeRule() {
        defaults.removeObject(forKey: Key.rule)
    }

    func markChanged(at date: Date = .now) {
        defaults.set(date, forKey: Key.lastChangeAt)
    }
}

/// Opens and closes the App Store to new installs.
enum InstallGate {
    nonisolated(unsafe) static let storeName = ManagedSettingsStore.Name("installWindow")
    nonisolated(unsafe) static let activityName = DeviceActivityName("prosper.installWindow")

    /// True when installs should be refused at `date`.
    static func deniesInstalls(rule: InstallWindowRule?, at date: Date, calendar: Calendar = .current) -> Bool {
        guard let rule else { return false }
        return rule.window(containing: date, calendar: calendar) == nil
    }

    /// Sets the gate from the saved rule and the clock.
    ///
    /// The monitor passes a moment a minute ahead when its own interval fires:
    /// iOS can deliver a callback a few seconds early, and a close delivered
    /// at 7:59:57 must still close.
    static func reconcile(at date: Date = .now) {
        // No App Group means no answer, and no answer must not open the gate.
        guard let state = InstallWindowState.appGroup else { return }
        let store = ManagedSettingsStore(named: storeName)
        guard let rule = state.rule else {
            store.clearAllSettings()
            return
        }
        store.application.denyAppInstallation = deniesInstalls(rule: rule, at: date) ? true : nil
    }
}
