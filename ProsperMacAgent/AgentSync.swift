import AppKit
import ProsperCore

/// The Mac's side of connected devices (PLAN.md M7.2). The agent runs all the
/// time, so it is the one that talks to iCloud: it publishes this Mac's day
/// and lock state, and writes what the user's other devices published to
/// `sync.json` for the app to show.
final class AgentSync {
    private let sync: CloudSync
    private let deviceID = MacStore.deviceID
    private let deviceName = Host.current().localizedName ?? "Mac"
    private var lastPublish = Date.distantPast
    private var lastFetch = Date.distantPast
    private var lastRequest = Date()
    private var busy = false

    static let publishInterval: TimeInterval = 60
    static let fetchInterval: TimeInterval = 120

    init() {
        sync = CloudSync(store: SyncStore(url: MacStore.syncURL, deviceID: deviceID), entitled: Self.hasICloud)
    }

    /// The no-filter install is signed without iCloud, and CloudKit traps
    /// without the entitlement, so ask macOS what this process was given.
    static var hasICloud: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
    }

    /// Once a second from the agent's timer. Does real work once a minute, or
    /// straight away when the app asks.
    func tick(rules: MacRules, now: Date = Date()) {
        guard !busy else { return }
        let requested = (try? MacStore.syncRequestURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        // A request is honoured at most every 10 s, however often the app asks.
        let asked = (requested.map { $0 > lastRequest } ?? false) && now.timeIntervalSince(lastFetch) >= 10
        let fetchDue = asked || now.timeIntervalSince(lastFetch) >= Self.fetchInterval
        guard asked || fetchDue || now.timeIntervalSince(lastPublish) >= Self.publishInterval else { return }
        if let requested { lastRequest = max(lastRequest, requested) }
        lastPublish = now
        if fetchDue { lastFetch = now }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let snapshot = MacSyncBuilder.snapshot(deviceID: deviceID, name: deviceName, rules: rules, appVersion: version, now: now)
        let settings = MacStore.loadSettings()
        let events = MacStore.read([MacEvent].self, from: MacStore.eventsURL) ?? []
        // Today and yesterday: yesterday's report settles after midnight.
        let days = [now, now.addingTimeInterval(-86_400)].compactMap { date -> DayReport? in
            guard let usage = MacStore.loadDay(DayReport.key(for: date)) else { return nil }
            return MacSyncBuilder.day(usage, deviceID: deviceID, settings: settings, rules: rules, events: events, now: now)
        }

        busy = true
        let sync = self.sync
        Task {
            await sync.publish(snapshot: snapshot, days: days)
            if fetchDue { await sync.syncNow() } else { await sync.refreshAccount() }
            DispatchQueue.main.async { self.busy = false }
        }
    }
}
