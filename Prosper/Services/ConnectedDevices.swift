import BackgroundTasks
import Foundation
import SwiftData
import UIKit

/// The iPhone's side of connected devices (PLAN.md M7.3, M7.5). Publishes
/// this iPhone's state to the user's private iCloud database and reads the
/// Mac's. Runs while the app is open (every minute), when it goes to the
/// background, and when iOS grants a background refresh.
@MainActor
final class ConnectedDevices: ObservableObject {
    static let shared = ConnectedDevices()
    static let refreshTaskID = "com.mostafa.prosper.sync"

    @Published private(set) var status = SyncStatus()
    @Published private(set) var devices: [RemoteDevice] = []

    let deviceID: String
    private let store: SyncStore
    private let sync: CloudSync
    private var timer: Timer?
    private var syncing = false

    private init() {
        deviceID = Self.loadDeviceID()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SyncStore(url: base.appendingPathComponent("Sync/sync.json"), deviceID: deviceID)
        sync = CloudSync(store: store, entitled: Self.hasICloud)
        reload()
    }

    /// Publishes this iPhone's state, then fetches the Mac's.
    func syncNow() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let (snapshot, days) = build()
        await sync.publish(snapshot: snapshot, days: days)
        await sync.syncNow()
        reload()
    }

    /// While the app is on screen: now, then every minute.
    func appBecameActive() {
        Task { await syncNow() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await ConnectedDevices.shared.syncNow() }
        }
        Self.scheduleBackgroundRefresh()
    }

    /// Leaving the screen: one last send, inside the time iOS allows.
    func appWentToBackground() {
        timer?.invalidate()
        timer = nil
        let task = UIApplication.shared.beginBackgroundTask(withName: "sync")
        Task {
            await syncNow()
            UIApplication.shared.endBackgroundTask(task)
        }
        Self.scheduleBackgroundRefresh()
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func reload() {
        let file = store.snapshot
        if status != file.status { status = file.status }
        var devices = file.devices
        #if targetEnvironment(simulator)
        // The simulator has no iCloud here; show a sample Mac so the layout
        // can be seen, the way the report views show sample usage.
        if devices.isEmpty { devices = [Self.sampleMac] }
        #endif
        if self.devices != devices { self.devices = devices }
    }

    #if targetEnvironment(simulator)
    static var sampleMac: RemoteDevice {
        let now = Date.now
        let key = DayReport.key(for: now)
        return RemoteDevice(
            snapshot: DeviceSnapshot(deviceID: "sample-mac", name: "MacBook Pro", platform: .mac, updatedAt: now.addingTimeInterval(-120),
                                     guardOn: true, guardSince: now.addingTimeInterval(-2 * 86_400)),
            days: [key: DayReport(deviceID: "sample-mac", day: key, measurement: .exact, totalSeconds: 5 * 3600 + 20 * 60,
                                  classSeconds: ["productive": 3 * 3600, "distracting": 4500, "rest": 1200, "unclassified": 1500],
                                  top: [UsageLine(name: "Xcode", kind: .app, seconds: 2 * 3600, opens: 6, timeClass: "productive"),
                                        UsageLine(name: "YouTube", kind: .platform, seconds: 2700, opens: 9, timeClass: "distracting"),
                                        UsageLine(name: "Slack", kind: .app, seconds: 1800, opens: 22, timeClass: "productive"),
                                        UsageLine(name: "Reddit", kind: .platform, seconds: 1200, opens: 5, timeClass: "distracting")],
                                  unlocks: 14, blockedAttempts: 3)]
        )
    }
    #endif

    // MARK: - What this iPhone shares

    private func build(now: Date = .now) -> (DeviceSnapshot, [DayReport]) {
        let context = PersistenceConfig.sharedModelContainer.mainContext
        let since = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: now)) ?? now
        let sessions = ((try? context.fetch(FetchDescriptor<BlockSession>())) ?? [])
            .filter { $0.endTime >= since }
            .map { PhoneSyncBuilder.Session(startedAt: $0.startedAt, endsAt: $0.endTime, domains: $0.domains, appCount: $0.appCount) }
        let warnings = ((try? context.fetch(FetchDescriptor<WarningEvent>(predicate: #Predicate { $0.timestamp >= since }))) ?? [])
            .map { PhoneSyncBuilder.Warning(level: $0.level, text: $0.triggerReason, at: $0.timestamp) }
        let schedules = ScheduledLockStore.load().map {
            PhoneSyncBuilder.Schedule(name: $0.name, startMinute: $0.startMinute, endMinute: $0.endMinute,
                                      weekdays: $0.weekdays, isOnNow: $0.window(containing: now) != nil)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let snapshot = PhoneSyncBuilder.snapshot(deviceID: deviceID, sessions: sessions, schedules: schedules,
                                                 guardSince: SharedGuardState.appGroup?.enabledAt,
                                                 measuresWaste: WasteMonitorRecord.appGroup.map { $0.fingerprint != nil && $0.failure == nil } ?? false,
                                                 appVersion: version, now: now)
        let days = [now, now.addingTimeInterval(-86_400)].map { date in
            let key = DayReport.key(for: date)
            return PhoneSyncBuilder.day(key, deviceID: deviceID, marks: WasteMarkLog.marks(day: key),
                                        sessions: sessions, warnings: warnings, now: now)
        }
        return (snapshot, days)
    }

    /// Device builds are always signed with the iCloud entitlement; simulator
    /// builds here are not (tests, screenshots), and CloudKit traps without it.
    static var hasICloud: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    /// Made once and kept, so this iPhone stays one device across launches.
    private static func loadDeviceID() -> String {
        let key = "sync.deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
