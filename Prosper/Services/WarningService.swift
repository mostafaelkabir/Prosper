import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Schedules the daily DeviceActivity that watches the user's waste selection
/// and fires when it crosses the threshold. The actual warning notification is
/// delivered by the `ProsperMonitor` extension (see `eventDidReachThreshold`),
/// which runs even when the app is not in the foreground.
final class WarningService: @unchecked Sendable {
    static let shared = WarningService()

    private let center = DeviceActivityCenter()

    private init() {}

    /// (Re)installs the daily monitor. Call after Settings changes and on app
    /// launch. Passing `enabled: false`, an empty selection, or no domains
    /// stops monitoring instead of scheduling an unusable event.
    func refreshSchedule(
        enabled: Bool,
        selection: FamilyActivitySelection,
        typedDomains: [String],
        thresholdMinutes: Int
    ) {
        center.stopMonitoring([PersistenceConfig.wasteActivityName])

        guard enabled, thresholdMinutes > 0 else { return }
        let hasAnyWaste = !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
            || !typedDomains.isEmpty
        guard hasAnyWaste else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: thresholdMinutes)
        )

        do {
            try center.startMonitoring(
                PersistenceConfig.wasteActivityName,
                during: schedule,
                events: [PersistenceConfig.wasteThresholdEvent: event]
            )
        } catch {
            print("WarningService: failed to schedule waste monitor: \(error)")
        }
    }

    func stop() {
        center.stopMonitoring([PersistenceConfig.wasteActivityName])
    }
}

/// Decodes / encodes a `FamilyActivitySelection` for SwiftData.
enum WasteSelectionCodec {
    static func decode(_ data: Data?) -> FamilyActivitySelection {
        guard let data else { return FamilyActivitySelection() }
        return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data))
            ?? FamilyActivitySelection()
    }

    static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }
}
