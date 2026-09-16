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
