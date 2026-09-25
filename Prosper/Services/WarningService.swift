import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import os.log

private let logger = Logger(subsystem: "com.mostafa.prosper", category: "warnings")

/// Schedules the daily DeviceActivity that watches the user's waste selection
/// and fires as it crosses each rung of the warning ladder. The warnings
/// themselves are delivered by the `ProsperMonitor` extension (see
/// `eventDidReachThreshold`), which runs even when the app is not in the
/// foreground.
final class WarningService: @unchecked Sendable {
    static let shared = WarningService()

    private let center = DeviceActivityCenter()

    private init() {}

    /// Installs the daily monitor, or leaves it alone when nothing about it
    /// has changed. Call after Settings changes and on app launch.
    ///
    /// Only the apps, categories and sites picked with Apple's picker are
    /// counted — iOS measures tokens, not typed text. Typed sites and platform
    /// tags are for blocking; a waste list with nothing else stops the monitor
    /// rather than scheduling events with empty token sets (QA-9). Passing
    /// `enabled: false` stops it too.
    func refreshSchedule(
        enabled: Bool,
        selection: FamilyActivitySelection,
        typedDomains: [String],
        thresholdMinutes: Int
    ) {
        let request = WasteMonitorRequest(
            enabled: enabled,
            thresholdMinutes: thresholdMinutes,
            applicationTokenCount: selection.applicationTokens.count,
            categoryTokenCount: selection.categoryTokens.count,
            webDomainTokenCount: selection.webDomainTokens.count,
            typedDomainCount: typedDomains.count,
            selectionData: WasteSelectionCodec.encode(selection)
        )
        let record = WasteMonitorRecord.appGroup

        guard request.shouldSchedule else {
            center.stopMonitoring([PersistenceConfig.wasteActivityName])
            record?.clear()
            if !enabled || thresholdMinutes <= 0 {
                // Warnings off — drop an intervention the user never saw rather
                // than ambushing them with it on the next launch.
                WarningInterventionState.clear()
            }
            return
        }

        // Re-installing an identical monitor is not free: iOS restarts its
        // count for the day, so warnings the user already had could repeat and
        // ones they were owed could slip. Leave a live, matching monitor be
        // (QA-9).
        let fingerprint = request.fingerprint
        if record?.fingerprint == fingerprint,
           center.activities.contains(PersistenceConfig.wasteActivityName) {
            return
        }

        center.stopMonitoring([PersistenceConfig.wasteActivityName])

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
            events[level.eventName] = Self.event(for: selection, minutes: minutes)
        }
        guard !events.isEmpty else { return }

        do {
            try center.startMonitoring(
                PersistenceConfig.wasteActivityName,
                during: schedule,
                events: events
            )
            record?.fingerprint = fingerprint
            record?.failure = nil
        } catch {
            // Without this the only trace was a print nobody reads, and the
            // user believed they were covered (QA-9).
            logger.error("Failed to schedule waste monitor: \(String(describing: error), privacy: .public)")
            record?.fingerprint = nil
            record?.failure = Self.failureMessage(for: error)
        }
    }

    func stop() {
        center.stopMonitoring([PersistenceConfig.wasteActivityName])
        WasteMonitorRecord.appGroup?.clear()
    }

    /// Why warnings are not running, in words for the user; nil when the last
    /// attempt to schedule them worked.
    var lastFailure: String? {
        WasteMonitorRecord.appGroup?.failure
    }

    /// On iOS 17.4+ the event counts the whole day, not just the time since it
    /// was installed — so a reinstall at 3pm still knows about the morning.
    /// The monitor's delivery ledger stops a rung already delivered today
    /// from arriving twice (QA-9).
    private static func event(for selection: FamilyActivitySelection, minutes: Int) -> DeviceActivityEvent {
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: minutes),
                includesPastActivity: true
            )
        }
        return DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: minutes)
        )
    }

    private static func failureMessage(for error: Error) -> String {
        switch error as? DeviceActivityCenter.MonitoringError {
        case .unauthorized:
            return "Warnings aren't running: iOS says StolenEyes no longer has Screen Time access. Turn it back on in Settings ▸ Screen Time, then reopen StolenEyes."
        case .excessiveActivities:
            return "Warnings aren't running: iOS refused because too many Screen Time schedules are active. Try again after your current block ends."
        default:
            return "Warnings aren't running: iOS wouldn't start watching your waste list. Change a setting here to try again, or reopen StolenEyes."
        }
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
