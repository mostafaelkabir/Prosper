import Foundation
import SwiftData

@Model
final class BlockSession {
    var id: UUID
    var blockedAppTokens: [String]
    var blockedWebDomains: [String]
    var duration: TimeInterval
    var startedAt: Date
    var createdAt: Date

    var isActive: Bool {
        Date.now < startedAt.addingTimeInterval(duration)
    }

    var remainingTime: TimeInterval {
        max(0, startedAt.addingTimeInterval(duration).timeIntervalSince(Date.now))
    }

    var endTime: Date {
        startedAt.addingTimeInterval(duration)
    }

    init(
        blockedAppTokens: [String] = [],
        blockedWebDomains: [String] = [],
        duration: TimeInterval,
        startedAt: Date = .now
    ) {
        self.id = UUID()
        self.blockedAppTokens = blockedAppTokens
        self.blockedWebDomains = blockedWebDomains
        self.duration = duration
        self.startedAt = startedAt
        self.createdAt = .now
    }
}
