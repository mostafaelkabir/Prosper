import Foundation

/// A tiny snapshot of the active block written to the shared App Group, so the
/// Shield extension can describe the block (when it was set, how much is left)
/// without opening SwiftData — which is too heavy for a ShieldConfiguration
/// extension. Written by `BlockingService` on start and cleared on end.
enum SharedBlockState {
    /// Must match `PersistenceConfig.appGroupID`. Duplicated here so the Shield
    /// target can compile this file without pulling in SwiftData / DeviceActivity.
    static let appGroupID = "group.com.mostafa.prosper"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    private static let startKey = "activeBlock.startedAt"
    private static let endKey = "activeBlock.endsAt"
    private static let durationKey = "activeBlock.duration"

    struct Snapshot {
        let startedAt: Date
        let endsAt: Date
        let duration: TimeInterval
        var remaining: TimeInterval { max(0, endsAt.timeIntervalSinceNow) }
    }

    static func save(startedAt: Date, duration: TimeInterval) {
        guard let defaults else { return }
        defaults.set(startedAt, forKey: startKey)
        defaults.set(startedAt.addingTimeInterval(duration), forKey: endKey)
        defaults.set(duration, forKey: durationKey)
    }

    static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: startKey)
        defaults.removeObject(forKey: endKey)
        defaults.removeObject(forKey: durationKey)
    }

    /// The active block snapshot, or nil when none is stored or it has expired.
    static var active: Snapshot? {
        guard let snapshot = stored, snapshot.endsAt.timeIntervalSinceNow > 0 else { return nil }
        return snapshot
    }

    /// The stored snapshot whether or not its timer has run out. Callers that
    /// must distinguish "no block was ever recorded" from "a block ended" need
    /// this; `active` collapses both to nil.
    static var stored: Snapshot? {
        guard let defaults,
              let start = defaults.object(forKey: startKey) as? Date,
              let end = defaults.object(forKey: endKey) as? Date else { return nil }
        return Snapshot(startedAt: start, endsAt: end, duration: defaults.double(forKey: durationKey))
    }

    /// True when a block was recorded and its timer has run out — the state a
    /// sweep is allowed to clean up. Deliberately false when nothing is stored,
    /// so a missing snapshot can never be read as "expired" (REL-7).
    static var hasExpired: Bool {
        guard let stored else { return false }
        return stored.endsAt.timeIntervalSinceNow <= 0
    }
}
