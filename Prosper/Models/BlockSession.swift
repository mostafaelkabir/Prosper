import Foundation
import SwiftData

@Model
final class BlockSession {
    var id: UUID
    var appCount: Int
    var domainCount: Int
    /// Websites the user typed in by domain (e.g. "reddit.com"). Blocked via the
    /// system web content filter, independent of the FamilyActivityPicker tokens.
    var domains: [String] = []
    var selectionData: Data?
    var duration: TimeInterval
    var startedAt: Date
    var createdAt: Date

    /// The shortest block that counts as a real focus session. Below this it's a
    /// trial run, not an achievement — so it must never inflate the streak or the
    /// milestone (UX-21). Keeping the streak earned is what makes it mean anything.
    static let minMeaningfulFocus: TimeInterval = 15 * 60

    var isActive: Bool {
        Date.now < startedAt.addingTimeInterval(duration)
    }

    /// A genuinely-completed focus session: it ran to the end and lasted at least
    /// `minMeaningfulFocus`. Only these count toward the streak, the completed
    /// count and the milestone, so the numbers stay true.
    var countsAsFocus: Bool {
        !isActive && duration >= Self.minMeaningfulFocus
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
        domains: [String] = [],
        selectionData: Data? = nil,
        duration: TimeInterval,
        startedAt: Date = .now
    ) {
        self.id = UUID()
        self.appCount = appCount
        self.domainCount = domainCount
        self.domains = domains
        self.selectionData = selectionData
        self.duration = duration
        self.startedAt = startedAt
        self.createdAt = .now
    }
}
