import DeviceActivity
import ManagedSettings
import Foundation
import SwiftData
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper.monitor", category: "activity")

// Logged at notice, not info: iOS drops info from saved logs, and the first
// device run had no trace of where a callback stopped (QA-10).
class ProsperDeviceActivityMonitor: DeviceActivityMonitor {
    let store = ManagedSettingsStore()

    override init() {
        super.init()
        logger.notice("Monitor created")
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        logger.notice("Monitoring interval started: \(activity.rawValue, privacy: .public)")
        if let lock = ScheduledLockStore.lock(for: activity) {
            startScheduledLock(lock)
        }
        sweepExpiredBlockIfNeeded()
        logger.notice("intervalDidStart done: \(activity.rawValue, privacy: .public)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        logger.notice("Monitoring interval ended: \(activity.rawValue, privacy: .public)")

        if activity == PersistenceConfig.unblockActivityName
            || activity == PersistenceConfig.unblockSafetyActivityName {
            // Replacing a schedule ends its interval too. A newer schedule under
            // this name is still running, so nothing ran out: neither lift nor
            // re-arm, or the re-arm ends the other timer and they loop (QA-10).
            if UnblockSchedule.wasSuperseded(registeredEnd: UnblockSchedule.registeredEnd(of: activity)) {
                logger.notice("Unblock interval \(activity.rawValue, privacy: .public) superseded by a newer schedule; ignoring")
                return
            }
            // The schedule is wall-clock date parts, so a time-zone change or a
            // daylight-saving fall-back can end the interval before the block's
            // real end. The snapshot holds the absolute end time; if it is still
            // well in the future, this is not the timer running out — re-arm
            // instead of lifting, or changing zones becomes a way out (QA-9).
            if let block = SharedBlockState.stored,
               block.endsAt.timeIntervalSinceNow > UnblockSchedule.earlyEndTolerance {
                let installed = UnblockSchedule.install(from: .now, to: block.endsAt)
                logger.notice("Unblock interval \(activity.rawValue, privacy: .public) ended \(Int(block.endsAt.timeIntervalSinceNow))s early; re-armed: \(installed)")
                return
            }
            clearBlock(reason: "interval \(activity.rawValue) ended")
        } else if let lock = ScheduledLockStore.lock(for: activity) {
            endScheduledLock(lock)
        } else {
            sweepExpiredBlockIfNeeded()
        }
    }

    // MARK: - Scheduled locks (E3.6)

    /// iOS opens the interval every day; the lock's own weekdays decide
    /// whether today counts. Asked a minute ahead so an interval delivered a
    /// few seconds early still finds its window.
    private func startScheduledLock(_ lock: ScheduledLock) {
        guard lock.window(containing: Date.now.addingTimeInterval(60)) != nil else {
            logger.notice("Scheduled lock \(lock.name, privacy: .public) is not set for today; leaving it off")
            return
        }
        ScheduledLockShield.apply(lock)
        logger.notice("Scheduled lock \(lock.name, privacy: .public) on")
    }

    /// Lifts the lock unless its window is plainly still open: an interval
    /// ended by a time-zone or clock change must not become a way out, the
    /// same rule the manual block follows (QA-9).
    private func endScheduledLock(_ lock: ScheduledLock) {
        if let window = lock.window(containing: .now),
           window.end.timeIntervalSinceNow > UnblockSchedule.earlyEndTolerance {
            logger.notice("Scheduled lock \(lock.name, privacy: .public) interval ended early; keeping it on")
            return
        }
        ScheduledLockShield.clear(lock)
        logger.notice("Scheduled lock \(lock.name, privacy: .public) off")
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        logger.notice("Threshold reached — event: \(event.rawValue, privacy: .public), activity: \(activity.rawValue, privacy: .public)")
        sweepExpiredBlockIfNeeded()

        guard activity == PersistenceConfig.wasteActivityName,
              let level = WarningLevel.level(for: event) else { return }

        // 1. Persist so the app can show a warning history and a rough
        // "time wasted today" number that survives the extension exiting.
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let settings = UserSettings.current(context: context)
        let minutes = level.thresholdMinutes(base: settings.wasteWarningThresholdMinutes)

        // 0. A reinstalled monitor that counts the whole day can reach a rung
        // the user was already given this morning. Deliver each rung once per
        // day per threshold — no duplicate row, no second notification (QA-9).
        if let ledger = WarningDeliveryLedger.appGroup,
           !ledger.claim(level, thresholdMinutes: minutes) {
            logger.notice("Level \(level.rawValue) at \(minutes)m already delivered today; skipping")
            return
        }

        let warning = WarningEvent(
            level: level.rawValue,
            triggerReason: level.triggerReason(minutes: minutes),
            appName: nil
        )
        context.insert(warning)
        try? context.save()

        // 2. Level 3 is more than a notification: flag the intervention the app
        // owes the user, so it interrupts properly the next time Prosper opens
        // even if the notification was swiped away.
        if level == .intervention {
            WarningInterventionState.record(minutes: minutes)
        }

        // 3. Deliver the notification for this rung.
        let content = UNMutableNotificationContent()
        content.title = level.notificationTitle
        content.body = level.notificationBody(minutes: minutes)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "prosper.waste.\(level.rawValue).\(Int(Date.now.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to post waste notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Expiry safety net (REL-7)

    /// Lifts a block whose timer has already run out.
    ///
    /// The block ending depends on iOS delivering `intervalDidEnd`, and it does
    /// not always: a reboot, an evicted extension or a schedule iOS declined
    /// (anything under about fifteen minutes) all drop it silently, and then the
    /// shield and the Safari filter simply stay on. For one user who knows the
    /// app that is an annoyance; for a stranger it is being locked out of their
    /// phone with no way back in.
    ///
    /// So every wake-up this extension gets — including the daily waste
    /// interval, which fires whether or not a block exists — is used to check.
    /// It reads the App Group snapshot rather than SwiftData because it must
    /// work in an extension that may have nothing else loaded, and because a
    /// missing snapshot reads as "no block", never as "expired".
    private func sweepExpiredBlockIfNeeded() {
        guard SharedBlockState.hasExpired else { return }
        clearBlock(reason: "sweep found a block past its end time")
    }

    /// Takes the restrictions off and forgets the block.
    ///
    /// No notification is posted here. The "block finished" message is a local
    /// notification scheduled when the block starts, which needs no extension to
    /// be alive and survives a reboot — so it arrives exactly once whether this
    /// callback ran or not.
    private func clearBlock(reason: String) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
        SharedBlockState.clear()
        logger.notice("Block cleared — shield and web filter removed (\(reason, privacy: .public))")
    }
}
