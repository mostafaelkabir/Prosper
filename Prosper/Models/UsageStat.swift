import Foundation
import SwiftData

@Model
final class UsageStat {
    var id: UUID
    var date: Date
    var appName: String
    var bundleIdentifier: String
    var category: String
    var duration: TimeInterval
    var isWaste: Bool
    var pickupCount: Int

    init(
        date: Date,
        appName: String,
        bundleIdentifier: String,
        category: String = "Other",
        duration: TimeInterval = 0,
        isWaste: Bool = false,
        pickupCount: Int = 0
    ) {
        self.id = UUID()
        self.date = date
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.category = category
        self.duration = duration
        self.isWaste = isWaste
        self.pickupCount = pickupCount
    }
}
