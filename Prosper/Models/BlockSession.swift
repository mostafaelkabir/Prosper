import Foundation
import SwiftData

@Model
final class BlockSession {
    var id: UUID
    var appCount: Int
    var domainCount: Int
    var selectionData: Data?
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
        appCount: Int = 0,
        domainCount: Int = 0,
        selectionData: Data? = nil,
        duration: TimeInterval,
        startedAt: Date = .now
    ) {
        self.id = UUID()
        self.appCount = appCount
        self.domainCount = domainCount
        self.selectionData = selectionData
        self.duration = duration
        self.startedAt = startedAt
        self.createdAt = .now
    }
}
