import DeviceActivity
import ManagedSettings
import Foundation
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
            logger.info("Block cleared — shield removed")
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        logger.info("Threshold reached — event: \(event.rawValue), activity: \(activity.rawValue)")
    }
}
