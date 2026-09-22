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

        let startedAt = Date.now
        scheduleUnblock(from: startedAt, duration: duration)
        scheduleEndNotification(duration: duration)
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
        guard !running.contains(PersistenceConfig.unblockActivityName)
                || !running.contains(PersistenceConfig.unblockSafetyActivityName) else { return }

        scheduleUnblock(from: snapshot.startedAt, duration: snapshot.duration)
        scheduleEndNotification(duration: snapshot.remaining, identifier: Self.endNotificationID)
    }

    var hasActiveBlock: Bool {
        store.shield.applications != nil
            || store.shield.webDomains != nil
            || store.webContent.blockedByFilter != nil
    }

    /// iOS refuses a `DeviceActivitySchedule` whose interval is shorter than
    /// about fifteen minutes, which is why a short block cannot rely on the
    /// primary schedule alone.
    private static let minimumScheduleSpan: TimeInterval = 16 * 60
    /// How long after the block ends the safety interval closes.
    private static let safetyGrace: TimeInterval = 5 * 60
    static let endNotificationID = "prosper.block.end"

    /// Installs both unblock timers: the exact one, and a second that closes a
    /// few minutes later. They are independent activities, so losing one still
    /// leaves a path that lifts the block without the user's help (REL-7).
    private func scheduleUnblock(from startedAt: Date, duration: TimeInterval) {
        let endDate = startedAt.addingTimeInterval(duration)

        start(PersistenceConfig.unblockActivityName, from: startedAt, to: endDate)

        // The safety interval is kept to a short window ending after the block
        // so its span is always a legal length without ever spanning a whole
        // day: for a five-minute block it starts with the block, for a long one
        // it opens shortly before the end.
        let safetyEnd = max(
            endDate.addingTimeInterval(Self.safetyGrace),
            startedAt.addingTimeInterval(Self.minimumScheduleSpan)
        )
        let safetyStart = max(startedAt, safetyEnd.addingTimeInterval(-Self.minimumScheduleSpan))
        start(PersistenceConfig.unblockSafetyActivityName, from: safetyStart, to: safetyEnd)
    }

    private func start(_ activity: DeviceActivityName, from start: Date, to end: Date) {
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(fields, from: start),
            intervalEnd: Calendar.current.dateComponents(fields, from: end),
            repeats: false
        )

        do {
            try activityCenter.startMonitoring(activity, during: schedule)
        } catch {
            // A refused schedule is survivable — the other timer, the monitor's
            // sweep and the foreground sweep all still end the block — but it is
            // the reason a block can overstay, so it is worth the log line.
            print("Failed to schedule \(activity.rawValue): \(error)")
        }
    }

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
