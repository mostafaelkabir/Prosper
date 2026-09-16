import Foundation
import SwiftData

@Model
final class UserSettings {
    var id: UUID
    var dailyScreenTimeGoal: TimeInterval
    var maxSocialMediaMinutes: Int
    var continuousUseWarningMinutes: Int
    var wasteAppBundleIDs: [String]
    var wasteDomains: [String]
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
        self.wasteAppBundleIDs = []
        self.wasteDomains = []
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
