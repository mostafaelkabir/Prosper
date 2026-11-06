import Foundation
import DeviceActivity
import FamilyControls
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper", category: "schedules")

/// Saves scheduled locks and keeps iOS's timers in step with them (E3.6).
///
/// A schedule is frozen while its window is open: it cannot be edited, turned
/// off or deleted until the window closes, so a schedule is never a way out of
/// the lock it is running. Outside its window it is the user's to change.
final class ScheduledLockService: @unchecked Sendable {
    static let shared = ScheduledLockService()

    /// iOS monitors at most 20 activities per app, and the daily usage, waste
    /// and two unblock timers already take four.
    static let maxLocks = 8

    private let center = DeviceActivityCenter()
    /// Serial, so registrations land in the order they were saved. Off the
    /// main thread because every DeviceActivity call can wait on ProsperMonitor
    /// (QA-10).
    private let queue = DispatchQueue(label: "com.mostafa.prosper.schedules", qos: .utility)

    private init() {}

    enum EditError: LocalizedError, Equatable {
        case lockedNow(until: Date)
        case tooShort
        case noDays
        case nothingSelected
        case tooManySites
        case tooManySchedules

        var errorDescription: String? {
            switch self {
            case .lockedNow(let until):
                return "This schedule is locking right now. It can be changed after \(until.formatted(date: .omitted, time: .shortened))."
            case .tooShort:
                return "A schedule has to run for at least 15 minutes. iOS cannot time anything shorter."
            case .noDays:
                return "Pick at least one day."
            case .nothingSelected:
                return "Pick at least one app, category or website to lock."
            case .tooManySites:
                return "iOS can filter at most \(BlockingService.maxDomains) websites at once."
            case .tooManySchedules:
                return "You can have up to \(ScheduledLockService.maxLocks) schedules."
            }
        }
    }

    var locks: [ScheduledLock] { ScheduledLockStore.load() }

    /// The end of the window `lock` is in right now, or nil when it is off and
    /// free to change.
    func frozenUntil(_ lock: ScheduledLock, now: Date = .now) -> Date? {
        lock.window(containing: now)?.end
    }

    static func validate(_ lock: ScheduledLock) -> EditError? {
        if lock.weekdays.isEmpty { return .noDays }
        if lock.lockedItemCount == 0 { return .nothingSelected }
        if lock.domains.count > BlockingService.maxDomains { return .tooManySites }
        if TimeInterval(lock.spanMinutes * 60) < UnblockSchedule.minimumSpan { return .tooShort }
        return nil
    }

    /// Adds or replaces a schedule. If the new times cover now, it locks
    /// straight away.
    func save(_ lock: ScheduledLock) throws {
        var all = locks
        if let existing = all.first(where: { $0.id == lock.id }) {
            if let until = frozenUntil(existing) { throw EditError.lockedNow(until: until) }
        } else if all.count >= Self.maxLocks {
            throw EditError.tooManySchedules
        }
        if let problem = Self.validate(lock) { throw problem }

        all.removeAll { $0.id == lock.id }
        all.append(lock)
        ScheduledLockStore.save(all)
        if frozenUntil(lock) != nil {
            ScheduledLockShield.apply(lock)
        } else {
            ScheduledLockShield.clear(lock)
        }
        queue.async { [self] in register(lock) }
    }

    /// Adds apps and websites to a schedule, including one that is locking
    /// right now (UX-22). Only adds, and leaves the times alone, so it can
    /// tighten a running schedule but never loosen or shorten it. The timer is
    /// not re-registered: replacing a running interval would end it early.
    func add(selection additions: FamilyActivitySelection, domains newDomains: [String], to lock: ScheduledLock) throws {
        guard var updated = locks.first(where: { $0.id == lock.id }) else { return }
        let domains = updated.domains + newDomains.filter { !updated.domains.contains($0) }
        guard domains.count <= BlockingService.maxDomains else { throw EditError.tooManySites }
        updated.domains = domains
        updated.selectionData = try? JSONEncoder().encode(BlockingService.merge(updated.selection, additions))

        ScheduledLockStore.save(locks.map { $0.id == updated.id ? updated : $0 })
        if frozenUntil(updated) != nil {
            ScheduledLockShield.apply(updated)
        }
    }

    func delete(_ lock: ScheduledLock) throws {
        if let until = frozenUntil(lock) { throw EditError.lockedNow(until: until) }
        ScheduledLockStore.save(locks.filter { $0.id != lock.id })
        ScheduledLockShield.clear(lock)
        queue.async { [self] in center.stopMonitoring([lock.activityName]) }
    }

    /// Brings shields and timers back in line on launch and foreground: a lock
    /// whose window is open is on, one whose window has closed is off (iOS can
    /// drop an interval callback after a reboot or eviction), and a timer iOS
    /// lost is put back.
    func reconcile() {
        let all = locks
        for lock in all {
            if frozenUntil(lock) != nil {
                ScheduledLockShield.apply(lock)
            } else {
                ScheduledLockShield.clear(lock)
            }
        }
        queue.async { [self] in
            let running = Set(center.activities)
            for lock in all where !running.contains(lock.activityName) {
                register(lock)
            }
        }
    }

    private func register(_ lock: ScheduledLock) {
        do {
            try center.startMonitoring(lock.activityName, during: lock.deviceActivitySchedule)
        } catch {
            logger.error("Failed to schedule \(lock.name, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
