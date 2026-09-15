import DeviceActivity
import Foundation
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper.monitor", category: "activity")

class ProsperDeviceActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        logger.info("Daily monitoring interval started: \(activity.rawValue)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        logger.info("Daily monitoring interval ended: \(activity.rawValue)")
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        logger.info("Threshold reached — event: \(event.rawValue), activity: \(activity.rawValue)")
    }
}
