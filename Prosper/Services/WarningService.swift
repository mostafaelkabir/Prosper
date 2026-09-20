import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Schedules the daily DeviceActivity that watches the user's waste selection
/// and fires as it crosses each rung of the warning ladder. The warnings
/// themselves are delivered by the `ProsperMonitor` extension (see
/// `eventDidReachThreshold`), which runs even when the app is not in the
/// foreground.
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

        guard enabled, thresholdMinutes > 0 else {
            // Warnings off — drop an intervention the user never saw rather
            // than ambushing them with it on the next launch.
            WarningInterventionState.clear()
            return
        }
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

        // One event per rung of the ladder (T, 2T, 3T). A rung that cannot fit
        // inside a single day is dropped instead of being scheduled and never
        // reached.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for level in WarningLevel.allCases {
            let minutes = level.thresholdMinutes(base: thresholdMinutes)
            guard minutes < 24 * 60 else { continue }
            events[level.eventName] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: minutes)
            )
        }
        guard !events.isEmpty else { return }

        do {
            try center.startMonitoring(
                PersistenceConfig.wasteActivityName,
                during: schedule,
                events: events
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
