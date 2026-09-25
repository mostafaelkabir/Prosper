import Foundation
import DeviceActivity

/// The two DeviceActivity timers that end a block, shared by the app (which
/// installs them when a block starts) and ProsperMonitor (which re-installs
/// them when one fires before the block is really over).
///
/// Kept apart from `BlockingService` so the monitor extension can compile it
/// without SwiftData, ManagedSettings or any UI (QA-9).
enum UnblockSchedule {
    /// iOS refuses a `DeviceActivitySchedule` whose interval is shorter than
    /// fifteen minutes. The safety window is a minute longer so it is never
    /// the one on the boundary.
    static let minimumSpan: TimeInterval = 15 * 60
    static let safetySpan: TimeInterval = 16 * 60
    /// How long after the block ends the safety interval closes.
    static let safetyGrace: TimeInterval = 5 * 60

    /// How early an unblock interval may end and still count as "on time".
    /// iOS fires to the minute, not the second; anything earlier than this is a
    /// clock or time-zone change, not the timer running out (QA-9).
    static let earlyEndTolerance: TimeInterval = 90

    struct Plan: Equatable {
        /// The exact timer, or nil when the time left is below iOS's minimum
        /// and only the safety window can be legal.
        let primary: DateInterval?
        let safety: DateInterval
    }

    /// The intervals that lift a block ending at `end`, installed at `now`.
    ///
    /// The safety interval is kept to a short window ending after the block so
    /// its span is always legal without ever spanning a whole day: for a short
    /// remainder it starts now, for a long one it opens shortly before the end.
    static func plan(from now: Date, to end: Date) -> Plan {
        let primary = end.timeIntervalSince(now) >= minimumSpan
            ? DateInterval(start: now, end: end)
            : nil
        let safetyEnd = max(end.addingTimeInterval(safetyGrace), now.addingTimeInterval(safetySpan))
        let safetyStart = max(now, safetyEnd.addingTimeInterval(-safetySpan))
        return Plan(primary: primary, safety: DateInterval(start: safetyStart, end: safetyEnd))
    }

    /// Installs both timers. Returns false only when iOS refused every one of
    /// them, which is the caller's cue that nothing will end this block.
    @discardableResult
    static func install(
        from now: Date,
        to end: Date,
        center: DeviceActivityCenter = DeviceActivityCenter()
    ) -> Bool {
        let plan = plan(from: now, to: end)
        var installed = false
        if let primary = plan.primary {
            installed = start(PersistenceConfig.unblockActivityName, primary, center: center) || installed
        } else {
            // A stale primary from an earlier install must not fire later and
            // be mistaken for this block's end.
            center.stopMonitoring([PersistenceConfig.unblockActivityName])
        }
        installed = start(PersistenceConfig.unblockSafetyActivityName, plan.safety, center: center) || installed
        #if targetEnvironment(simulator)
        // The simulator has no Screen Time, so iOS refuses every schedule and
        // nothing is enforced anyway. Reporting success keeps the Lock screen's
        // countdown testable there; the foreground sweep still ends the block.
        return true
        #else
        return installed
        #endif
    }

    private static func start(
        _ activity: DeviceActivityName,
        _ interval: DateInterval,
        center: DeviceActivityCenter
    ) -> Bool {
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(fields, from: interval.start),
            intervalEnd: Calendar.current.dateComponents(fields, from: interval.end),
            repeats: false
        )
        do {
            try center.startMonitoring(activity, during: schedule)
            return true
        } catch {
            print("Failed to schedule \(activity.rawValue): \(error)")
            return false
        }
    }
}
