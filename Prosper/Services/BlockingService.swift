import Foundation
import ManagedSettings
import FamilyControls
import DeviceActivity
import SwiftData

enum BlockStartError: LocalizedError {
    case alreadyActive
    case nothingSelected
    case scheduleFailed(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            return "A block is already running on this device. Wait for it to expire before starting another."
        case .nothingSelected:
            return "Pick at least one app or website first."
        case .scheduleFailed(let underlying):
            return "iOS refused to schedule the block: \(underlying.localizedDescription). Make sure Screen Time access is allowed and try again."
        }
    }
}

final class BlockingService: @unchecked Sendable {
    static let shared = BlockingService()

    /// Apple's web content filter accepts at most this many domains at once.
    static let maxDomains = 50

    /// iOS refuses to fire `intervalDidEnd` for scheduled intervals shorter
    /// than about 15 minutes, so the shield would linger forever. The UI
    /// caps at this value to keep the hard-lock promise honest.
    static let minimumDuration: TimeInterval = 15 * 60

    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()

    private init() {}

    /// Starts an unbreakable block.
    /// - Parameters:
    ///   - apps: App tokens chosen in the FamilyActivityPicker.
    ///   - webDomains: Website tokens chosen in the FamilyActivityPicker (only sites
    ///     that already appear in Safari history show up there).
    ///   - domains: Website domains the user typed in directly, e.g. "reddit.com".
    ///     Enforced by the system web content filter in Safari and other browsers,
    ///     on this device only.
    func startBlock(
        apps: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        domains: [String],
        duration: TimeInterval,
        selection: FamilyActivitySelection
    ) throws {
        // A truly stuck shield from an earlier interval that never fired
        // `intervalDidEnd` (e.g. a schedule shorter than iOS's ~15-minute
        // minimum) would otherwise wedge the app forever. Clean that up
        // first — this is NOT an early-cancel path, only stale bookkeeping.
        reconcileStaleShield()

        guard !hasActiveBlock else { throw BlockStartError.alreadyActive }

        let typedDomains = Array(domains.prefix(Self.maxDomains))
        guard !(apps.isEmpty && webDomains.isEmpty && typedDomains.isEmpty) else {
            throw BlockStartError.nothingSelected
        }

        // Ask once for notification permission so the block-end message can
        // reach the user. If the user declined earlier we don't re-prompt.
        Task { _ = await NotificationService.shared.requestPermission() }

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        if typedDomains.isEmpty {
            store.webContent.blockedByFilter = nil
        } else {
            store.webContent.blockedByFilter = .specific(Set(typedDomains.map { WebDomain(domain: $0) }))
        }

        do {
            try scheduleUnblock(duration: duration)
        } catch {
            // Roll back the shield so the app doesn't get stuck.
            clearBlock()
            throw BlockStartError.scheduleFailed(error)
        }
        persistBlockSession(
            selection: selection,
            appCount: apps.count,
            domainCount: webDomains.count + typedDomains.count,
            domains: typedDomains,
            duration: duration
        )
    }

    /// If the ManagedSettings store is holding a shield but no BlockSession
    /// is still time-active, iOS never fired `intervalDidEnd` (usually
    /// because the interval was under the 15-minute minimum). Clear it so
    /// the user can start a fresh block. Never touches a still-running one.
    func reconcileStaleShield() {
        guard hasActiveBlock else { return }
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let now = Date.now
        let descriptor = FetchDescriptor<BlockSession>()
        let sessions = (try? context.fetch(descriptor)) ?? []
        let liveSession = sessions.first { now < $0.startedAt.addingTimeInterval($0.duration) }
        if liveSession == nil {
            clearBlock()
        }
    }

    func clearBlock() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
        activityCenter.stopMonitoring([PersistenceConfig.unblockActivityName])
    }

    var hasActiveBlock: Bool {
        store.shield.applications != nil
            || store.shield.webDomains != nil
            || store.webContent.blockedByFilter != nil
    }

    private func scheduleUnblock(duration: TimeInterval) throws {
        let endDate = Date.now.addingTimeInterval(max(duration, Self.minimumDuration))
        let endComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: endDate
        )
        let startComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: .now
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        try activityCenter.startMonitoring(PersistenceConfig.unblockActivityName, during: schedule)
    }

    private func persistBlockSession(
        selection: FamilyActivitySelection,
        appCount: Int,
        domainCount: Int,
        domains: [String],
        duration: TimeInterval
    ) {
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let selectionData = try? JSONEncoder().encode(selection)
        let session = BlockSession(
            appCount: appCount,
            domainCount: domainCount,
            domains: domains,
            selectionData: selectionData,
            duration: duration
        )
        context.insert(session)
        try? context.save()
    }
}

/// Turns whatever the user typed ("https://www.Reddit.com/r/all", "youtube.com")
/// into a bare, lowercase domain suitable for `WebDomain(domain:)`.
enum BlockDomain {
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        if let schemeRange = s.range(of: "://") {
            s = String(s[schemeRange.upperBound...])
        }
        if let cut = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[..<cut])
        }
        if let at = s.lastIndex(of: "@") {
            s = String(s[s.index(after: at)...])
        }
        if let colon = s.firstIndex(of: ":") {
            s = String(s[..<colon])
        }
        if s.hasPrefix("www.") {
            s.removeFirst(4)
        }

        let allowed = s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
        guard allowed, s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."), !s.contains("..") else {
            return nil
        }
        return s
    }
}
