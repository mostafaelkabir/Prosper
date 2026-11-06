import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// A lock that switches itself on at set times, like bedtime or work focus
/// (E3.6). Shared by the app, which saves and registers it, and ProsperMonitor,
/// which applies its shields when the window opens and lifts them when it
/// closes.
///
/// Kept apart from SwiftData so the monitor can read it straight from the App
/// Group, the same way it reads `SharedBlockState`.
struct ScheduledLock: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Minutes after midnight. An end at or before the start runs past midnight.
    var startMinute: Int
    var endMinute: Int
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) a window *starts* on, so
    /// Friday's bedtime lock still runs into Saturday morning.
    var weekdays: Set<Int>
    /// Encoded `FamilyActivitySelection`: apps and categories to shield.
    var selectionData: Data?
    /// Typed websites for the web content filter.
    var domains: [String]

    static let activityPrefix = "prosper.schedule."

    var activityName: DeviceActivityName { DeviceActivityName(Self.activityPrefix + id.uuidString) }

    /// Each schedule shields through its own store, so its window closing
    /// never lifts a manual block or another schedule.
    var storeName: ManagedSettingsStore.Name { ManagedSettingsStore.Name(Self.activityPrefix + id.uuidString) }

    var crossesMidnight: Bool { endMinute <= startMinute }

    /// Length of one window in minutes.
    var spanMinutes: Int {
        crossesMidnight ? endMinute + 24 * 60 - startMinute : endMinute - startMinute
    }

    var selection: FamilyActivitySelection {
        guard let selectionData,
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) else {
            return FamilyActivitySelection()
        }
        return decoded
    }

    var lockedItemCount: Int {
        let selection = selection
        return selection.applicationTokens.count + selection.categoryTokens.count
            + selection.webDomainTokens.count + domains.count
    }

    /// The window that contains `date`, or nil when the lock is off then.
    ///
    /// Built from wall-clock hour and minute on each candidate day, not by
    /// adding minutes to midnight, so a daylight-saving day still opens at
    /// 10:00 PM rather than 9 or 11.
    func window(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        // Today's window, or yesterday's when it runs past midnight.
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

    /// The repeating daily interval iOS fires. Weekdays are checked when it
    /// opens: one activity per lock keeps the app well under iOS's cap of 20
    /// monitored activities, where one per weekday would not.
    var deviceActivitySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: startMinute / 60, minute: startMinute % 60),
            intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60),
            repeats: true
        )
    }
}

/// The saved schedules, as JSON in the App Group.
enum ScheduledLockStore {
    private static let key = "scheduledLocks.v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedBlockState.appGroupID) }

    static func load() -> [ScheduledLock] {
        guard let data = defaults?.data(forKey: key),
              let locks = try? JSONDecoder().decode([ScheduledLock].self, from: data) else { return [] }
        return locks
    }

    static func save(_ locks: [ScheduledLock]) {
        guard let data = try? JSONEncoder().encode(locks) else { return }
        defaults?.set(data, forKey: key)
    }

    /// The lock a DeviceActivity callback is about, if it is one of ours.
    static func lock(for activity: DeviceActivityName) -> ScheduledLock? {
        guard activity.rawValue.hasPrefix(ScheduledLock.activityPrefix) else { return nil }
        return load().first { $0.activityName == activity }
    }
}

/// Puts a schedule's restrictions on and takes them off.
enum ScheduledLockShield {
    static func apply(_ lock: ScheduledLock) {
        let store = ManagedSettingsStore(named: lock.storeName)
        let selection = lock.selection
        let categories = selection.categoryTokens
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        // The schedule's own names only; the Adult Content Guard holds its
        // filter in its own store (E9).
        store.webContent.blockedByFilter = AdultDomainList.sessionPolicy(domains: lock.domains)
    }

    static func clear(_ lock: ScheduledLock) {
        ManagedSettingsStore(named: lock.storeName).clearAllSettings()
    }
}
