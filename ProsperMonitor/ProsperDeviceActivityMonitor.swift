import DeviceActivity
import ManagedSettings
import Foundation
import SwiftData
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper.monitor", category: "activity")

class ProsperDeviceActivityMonitor: DeviceActivityMonitor {
    let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        logger.info("Monitoring interval started: \(activity.rawValue)")
        sweepExpiredBlockIfNeeded()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        logger.info("Monitoring interval ended: \(activity.rawValue)")

        if activity == PersistenceConfig.unblockActivityName
            || activity == PersistenceConfig.unblockSafetyActivityName {
            clearBlock(reason: "interval \(activity.rawValue) ended")
        } else {
            sweepExpiredBlockIfNeeded()
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        logger.info("Threshold reached — event: \(event.rawValue), activity: \(activity.rawValue)")
        sweepExpiredBlockIfNeeded()

        guard activity == PersistenceConfig.wasteActivityName,
              let level = WarningLevel.level(for: event) else { return }

        // 1. Persist so the app can show a warning history and a rough
        // "time wasted today" number that survives the extension exiting.
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let settings = UserSettings.current(context: context)
        let minutes = level.thresholdMinutes(base: settings.wasteWarningThresholdMinutes)
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
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
        SharedBlockState.clear()
        logger.info("Block cleared — shield and web filter removed (\(reason, privacy: .public))")
    }
}
