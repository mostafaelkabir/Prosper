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
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        logger.info("Threshold reached — event: \(event.rawValue), activity: \(activity.rawValue)")

        guard activity == PersistenceConfig.wasteActivityName,
              event == PersistenceConfig.wasteThresholdEvent else { return }

        // 1. Persist so the app can show a warning history and a rough
        // "time wasted today" number that survives the extension exiting.
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let settings = UserSettings.current(context: context)
        let minutes = settings.wasteWarningThresholdMinutes
        let warning = WarningEvent(
            level: 1,
            triggerReason: "Waste activity reached \(minutes) minutes today",
            appName: nil
        )
        context.insert(warning)
        try? context.save()

        // 2. Deliver the notification (Level 1 nudge — Level 2 / 3 come later).
        let content = UNMutableNotificationContent()
        content.title = "Prosper"
        content.body = "You've spent \(minutes) minutes on your waste list today. Step away for a moment."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "prosper.waste.\(minutes).\(Int(Date.now.timeIntervalSince1970))",
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
