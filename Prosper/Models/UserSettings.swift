import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID
    var dailyScreenTimeGoal: TimeInterval
    var maxSocialMediaMinutes: Int
    var continuousUseWarningMinutes: Int
    /// Encoded `FamilyActivitySelection` covering apps and category tokens the
    /// user labeled as time-waste. Persisted as opaque `Data` because
    /// `ApplicationToken`s themselves are opaque and per-device.
    var wasteAppSelectionData: Data?
    /// How many app+category tokens are selected. Kept in sync with
    /// `wasteAppSelectionData` so the UI does not have to decode the blob.
    var wasteAppCount: Int = 0
    var wasteAppBundleIDs: [String]
    var wasteDomains: [String]
    /// Minutes of combined waste-app / waste-site activity per day before a
    /// warning fires. Range enforced by the UI (5…240).
    var wasteWarningThresholdMinutes: Int = 30
    var warningsEnabled: Bool
    var level3PhraseRequired: Bool
    /// Websites the user last typed into the block creator, so the list is
    /// remembered between blocks (e.g. ["reddit.com", "youtube.com"]).
    var savedBlockDomains: [String] = []
    /// True once the user has finished (or explicitly skipped through) the
    /// post-authorization setup flow. Drives the "resume setup" banner.
    var hasCompletedSetup: Bool = false
    /// When the settings record was first created — i.e. first launch. Used to
    /// show honest "data is still accumulating" empty states on day one.
    var firstLaunchAt: Date = Date.now

    // MARK: - Time classification (UX-9)
    // The four classes are Productive / Distracting / Intentional rest /
    // Unclassified. "Distracting" reuses the existing waste list
    // (`wasteAppSelectionData` + `wasteDomains`) so warnings and quick-block
    // presets keep working and the migration is automatic. Everything not
    // explicitly listed stays Unclassified — nothing becomes productive by
    // subtraction.
    var productiveSelectionData: Data?
    var productiveDomains: [String] = []
    var restSelectionData: Data?
    var restDomains: [String] = []

    init() {
        self.id = UUID()
        self.dailyScreenTimeGoal = 7200
        self.maxSocialMediaMinutes = 30
        self.continuousUseWarningMinutes = 20
        self.wasteAppSelectionData = nil
        self.wasteAppCount = 0
        self.wasteAppBundleIDs = []
        self.wasteDomains = []
        self.wasteWarningThresholdMinutes = 30
        self.warningsEnabled = true
        self.level3PhraseRequired = true
        self.savedBlockDomains = []
        self.hasCompletedSetup = false
        self.firstLaunchAt = .now
        self.productiveSelectionData = nil
        self.productiveDomains = []
        self.restSelectionData = nil
        self.restDomains = []
    }

    /// True during the first calendar day after install, when Screen Time data
    /// has not yet had time to accumulate.
    var isFirstDay: Bool {
        Calendar.current.isDateInToday(firstLaunchAt)
    }

    static func current(context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = UserSettings()
        context.insert(settings)
        return settings
    }
}
