import Foundation
import ManagedSettings
import FamilyControls
import DeviceActivity
import SwiftData

final class BlockingService: @unchecked Sendable {
    static let shared = BlockingService()

    /// Apple's web content filter accepts at most this many domains at once.
    static let maxDomains = 50

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
    ) {
        guard !hasActiveBlock else { return }

        // Ask once for notification permission so the block-end message can
        // reach the user. If the user declined earlier we don't re-prompt.
        Task { _ = await NotificationService.shared.requestPermission() }

        let typedDomains = Array(domains.prefix(Self.maxDomains))

        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        if typedDomains.isEmpty {
            store.webContent.blockedByFilter = nil
        } else {
            store.webContent.blockedByFilter = .specific(Set(typedDomains.map { WebDomain(domain: $0) }))
        }

        scheduleUnblock(duration: duration)
        persistBlockSession(
            selection: selection,
            appCount: apps.count,
            domainCount: webDomains.count + typedDomains.count,
            domains: typedDomains,
            duration: duration
        )
    }

    func clearBlock() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
        activityCenter.stopMonitoring([PersistenceConfig.unblockActivityName])
        SharedBlockState.clear()
    }

    /// Lifts restrictions when the block's timer has already elapsed but the
    /// system never cleared them — e.g. the interval was below iOS's ~15-minute
    /// `DeviceActivityMonitor` minimum, the app was force-quit, or the device
    /// rebooted, so `intervalDidEnd` never fired and Safari stays filtered.
    ///
    /// This is NOT an early cancel (see CLAUDE.md): it only ever acts once no
    /// `BlockSession` is still within its timer, so an active block is untouched.
    /// Call on launch and whenever the app returns to the foreground.
    func clearExpiredBlockIfNeeded() {
        guard hasActiveBlock else { return }
        let context = ModelContext(PersistenceConfig.sharedModelContainer)
        let sessions = (try? context.fetch(FetchDescriptor<BlockSession>())) ?? []
        let stillLocked = sessions.contains { $0.isActive }
        if !stillLocked {
            clearBlock()
        }
    }

    var hasActiveBlock: Bool {
        store.shield.applications != nil
            || store.shield.webDomains != nil
            || store.webContent.blockedByFilter != nil
    }

    private func scheduleUnblock(duration: TimeInterval) {
        let endDate = Date.now.addingTimeInterval(duration)
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

        do {
            try activityCenter.startMonitoring(PersistenceConfig.unblockActivityName, during: schedule)
        } catch {
            print("Failed to schedule unblock: \(error)")
        }
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

        // Mirror the essentials to the App Group so the Shield extension can
        // describe this block (remaining time, when it was set).
        SharedBlockState.save(startedAt: session.startedAt, duration: duration)
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
