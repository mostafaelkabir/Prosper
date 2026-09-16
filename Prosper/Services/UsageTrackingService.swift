import Foundation
import DeviceActivity
import FamilyControls

final class UsageTrackingService: @unchecked Sendable {
    static let shared = UsageTrackingService()

    private let center = DeviceActivityCenter()
    nonisolated(unsafe) static let activityName = DeviceActivityName("prosper.daily")

    private init() {}

    func startDailyMonitoring() {
        let midnight = Calendar.current.startOfDay(for: .now)
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: midnight)

        let schedule = DeviceActivitySchedule(
            intervalStart: components,
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        do {
            try center.startMonitoring(Self.activityName, during: schedule)
        } catch {
            print("Failed to start device activity monitoring: \(error)")
        }
    }

    func stopMonitoring() {
        center.stopMonitoring([Self.activityName])
    }
}
