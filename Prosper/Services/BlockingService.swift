import Foundation
import ManagedSettings
import FamilyControls
import DeviceActivity
import SwiftData
import UserNotifications

final class BlockingService: @unchecked Sendable {
    static let shared = BlockingService()

    /// Apple's web content filter accepts at most this many domains at once.
    static let maxDomains = 50

    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()

    private init() {}

    /// Why a block did not start. Every case is shown to the user: a block that
    /// silently fails to start looks exactly like one that is running (QA-9).
    enum StartError: LocalizedError, Equatable {
        case alreadyRunning
        case nothingSelected
        case tooShort
        case tooManySites(Int)
        case couldNotSchedule

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "A block is already running. A new one can start when it ends."
            case .nothingSelected:
                return "Pick at least one app, category or website to lock."
            case .tooShort:
                return "The shortest block is 15 minutes. iOS cannot time anything shorter."
            case .tooManySites(let count):
                return "iOS can filter at most \(BlockingService.maxDomains) websites at once. Remove \(count - BlockingService.maxDomains) to continue."
            case .couldNotSchedule:
                return "iOS refused the timer that ends this block, so nothing was locked. Try again in a minute."
            }
        }
    }

    /// iOS refuses DeviceActivity schedules shorter than this, and a block
    /// without a working timer is one nothing in the app can end.
    static let minimumDuration: TimeInterval = UnblockSchedule.minimumSpan

    /// Checks a block before anything is applied, so the confirm screen can say
    /// what is wrong instead of locking half of what it listed.
    static func validate(
        selection: FamilyActivitySelection,
        domains: [String],
        duration: TimeInterval
    ) -> StartError? {
        if selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty
            && selection.webDomainTokens.isEmpty
            && domains.isEmpty {
            return .nothingSelected
        }
        if domains.count > maxDomains { return .tooManySites(domains.count) }
        if duration < minimumDuration { return .tooShort }
        return nil
    }

    /// Starts an unbreakable block.
    /// - Parameters:
    ///   - selection: What the FamilyActivityPicker returned: apps, Screen Time
    ///     categories, and websites that already appear in Safari history.
    ///   - domains: Website domains the user typed in directly, e.g. "reddit.com".
    ///     Enforced by the system web content filter in Safari and other browsers,
    ///     on this device only.
    ///
    /// The timers are installed before any restriction is applied: if iOS
    /// refuses them, nothing is locked and the user is told, rather than being
    /// left behind a shield that only the next app launch can lift.
    func startBlock(
        selection: FamilyActivitySelection,
        domains: [String],
        duration: TimeInterval
    ) throws {
        guard !hasActiveBlock, SharedBlockState.active == nil else { throw StartError.alreadyRunning }
        if let problem = Self.validate(selection: selection, domains: domains, duration: duration) {
            throw problem
        }

        // Ask once for notification permission so the block-end message can
        // reach the user. If the user declined earlier we don't re-prompt.
        Task { _ = await NotificationService.shared.requestPermission() }

        let startedAt = Date.now
        // The snapshot goes first: the monitor sweeps on every interval start,
        // and must find this block, not a stale one it would clear.
        SharedBlockState.save(startedAt: startedAt, duration: duration)
        guard UnblockSchedule.install(from: startedAt, to: startedAt.addingTimeInterval(duration), center: activityCenter) else {
            SharedBlockState.clear()
            throw StartError.couldNotSchedule
        }

        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        let webDomains = selection.webDomainTokens
        store.shield.applications = apps.isEmpty ? nil : apps
        // A category is how most people pick "all social media". It has to be
        // shielded on both the app side and the web side, or a category-only
        // block saves a countdown and locks nothing at all (QA-9).
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        if domains.isEmpty {
            store.webContent.blockedByFilter = nil
        } else {
            store.webContent.blockedByFilter = .specific(Set(domains.map { WebDomain(domain: $0) }))
        }

        scheduleEndNotification(duration: duration)
        persistBlockSession(
            selection: selection,
            startedAt: startedAt,
            // Categories count here so the Lock screen shows their chips.
            appCount: apps.count + categories.count,
            domainCount: webDomains.count + domains.count,
            domains: domains,
            duration: duration
        )
    }

    func clearBlock() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = nil
        activityCenter.stopMonitoring([
            PersistenceConfig.unblockActivityName,
            PersistenceConfig.unblockSafetyActivityName,
        ])
        SharedBlockState.clear()
    }

    /// Lifts restrictions when the block's timer has already elapsed but the
    /// system never cleared them — e.g. the interval was below iOS's ~15-minute
    /// `DeviceActivityMonitor` minimum, the app was force-quit, or the device
    /// rebooted, so `intervalDidEnd` never fired and Safari stays filtered.
    ///
    /// This is NOT an early cancel (see CLAUDE.md). It clears only when *every*
    /// record agrees the timer has run out: the App Group snapshot and the
    /// SwiftData sessions are consulted as a union, so either one still showing
    /// a live block leaves the shield exactly where it is. That union matters —
    /// asking SwiftData alone (as this did) meant a lost or reset store read as
    /// "nothing is running" and would have lifted a block that was very much
    /// running, turning a storage fault into the early cancel the app promises
    /// does not exist.
    ///
    /// Call on launch and whenever the app returns to the foreground.
    func clearExpiredBlockIfNeeded() {
        guard hasActiveBlock else { return }

        if SharedBlockState.active != nil { return }

        let context = ModelContext(PersistenceConfig.sharedModelContainer)
        let sessions = (try? context.fetch(FetchDescriptor<BlockSession>())) ?? []
        if sessions.contains(where: { $0.isActive }) { return }

        clearBlock()
    }

    /// Re-installs the unblock schedules for a block that is still running.
    ///
    /// DeviceActivity schedules are system state, and a reinstall, a restore or
    /// a long-evicted extension can lose them — at which point the only thing
    /// left to lift the block is the user reopening the app. Called on launch,
    /// this puts the timers back so the block can end on its own again.
    func reassertScheduleIfNeeded() {
        guard let snapshot = SharedBlockState.active else { return }
        let running = Set(activityCenter.activities)
        // Under fifteen minutes left there is deliberately no primary timer
        // (iOS would refuse it), so only a missing safety timer counts as lost.
        let primaryExpected = snapshot.remaining >= UnblockSchedule.minimumSpan
        let primaryLost = primaryExpected && !running.contains(PersistenceConfig.unblockActivityName)
        guard primaryLost || !running.contains(PersistenceConfig.unblockSafetyActivityName) else { return }

        UnblockSchedule.install(from: .now, to: snapshot.endsAt, center: activityCenter)
        scheduleEndNotification(duration: snapshot.remaining, identifier: Self.endNotificationID)
    }

    var hasActiveBlock: Bool {
        store.shield.applications != nil
            || store.shield.applicationCategories != nil
            || store.shield.webDomainCategories != nil
            || store.shield.webDomains != nil
            || store.webContent.blockedByFilter != nil
    }

    static let endNotificationID = "prosper.block.end"

    /// A local notification timed to the end of the block.
    ///
    /// Unlike the DeviceActivity callbacks this needs no extension to be alive
    /// and survives a reboot, so it is the path that still reaches the user when
    /// everything else is evicted: opening the app runs the foreground sweep.
    private func scheduleEndNotification(
        duration: TimeInterval,
        identifier: String = endNotificationID
    ) {
        guard duration > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Block finished"
        content.body = "Your StolenEyes block just expired. Nice work — the door is unlocked again."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        )
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(request)
    }

    private func persistBlockSession(
        selection: FamilyActivitySelection,
        startedAt: Date,
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
            duration: duration,
            // One start time everywhere: the snapshot, the timers and the session.
            startedAt: startedAt
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

        // An internationalised domain has to reach WebDomain as punycode. The
        // check below used Character.isLetter, which is true for "ü" and "中",
        // so "bücher.de" sailed through and was handed to the filter as UTF-8 —
        // accepted without complaint and blocking nothing. A site the user
        // believes is blocked and is not is the worst failure this type has, so
        // the conversion happens here and anything that will not convert is
        // refused out loud instead.
        if !s.allSatisfy(\.isASCII) {
            guard let encoded = URL(string: "https://" + s)?.host?.lowercased() else { return nil }
            s = encoded
        }

        let allowed = s.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "." }
        guard allowed, s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."), !s.contains("..") else {
            return nil
        }
        return s
    }
}
