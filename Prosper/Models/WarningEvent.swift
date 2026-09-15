import Foundation
import SwiftData

@Model
final class WarningEvent {
    var id: UUID
    var timestamp: Date
    var level: Int
    var triggerReason: String
    var appName: String?
    var acknowledged: Bool
    var acknowledgedAt: Date?

    init(
        level: Int,
        triggerReason: String,
        appName: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = .now
        self.level = level
        self.triggerReason = triggerReason
        self.appName = appName
        self.acknowledged = false
        self.acknowledgedAt = nil
    }
}
