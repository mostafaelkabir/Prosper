import DeviceActivity
import Foundation

class ProsperDeviceActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
    }
}
