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
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        logger.info("Monitoring interval ended: \(activity.rawValue)")

        if activity == PersistenceConfig.unblockActivityName {
            store.shield.applications = nil
            store.shield.webDomains = nil
            store.webContent.blockedByFilter = nil
            logger.info("Block cleared — shield and web filter removed")

            let content = UNMutableNotificationContent()
            content.title = "Block finished"
            content.body = "Your Prosper block just expired. Nice work — the door is unlocked again."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "prosper.block.end.\(Int(Date.now.timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    logger.error("Failed to post block-end notification: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        logger.info("Threshold reached — event: \(event.rawValue), activity: \(activity.rawValue)")

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
}
