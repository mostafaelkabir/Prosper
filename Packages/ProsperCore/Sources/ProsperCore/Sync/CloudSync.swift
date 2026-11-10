import CloudKit
import Foundation
import os.log

private let syncLog = Logger(subsystem: "com.mostafa.prosper", category: "sync")

/// Connects this device to the user's other devices through their private
/// iCloud database (PLAN.md M7). There is no account of ours: the Apple
/// Account signed in on the device is the identity, and only that account's
/// devices can read the data.
///
/// Each device publishes its own `DeviceSnapshot` and a `DayReport` per day
/// and reads everyone else's. Nothing here can change another device's lock
/// or guard: this is monitoring, and remote locks (M7.4) will only ever add.
public actor CloudSync: CKSyncEngineDelegate {
    public static let containerID = "iCloud.com.mostafa.prosper"

    public let store: SyncStore
    private let containerID: String
    /// False for a build signed without iCloud (unsigned test builds, the
    /// Mac's no-filter install): CloudKit traps the moment such a build
    /// touches a container, so it never does.
    private let entitled: Bool
    private var engine: CKSyncEngine?
    private lazy var container = CKContainer(identifier: containerID)

    public init(store: SyncStore, entitled: Bool, containerID: String = CloudSync.containerID) {
        self.store = store
        self.entitled = entitled
        self.containerID = containerID
    }

    /// Starts the engine (once) and checks the iCloud account.
    public func start() async {
        await refreshAccount()
        guard entitled, engine == nil else { return }
        let state = store.snapshot.engineState.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: state, delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !store.snapshot.zoneReady {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
        }
    }

    /// Records this device's state. Only real changes are sent.
    public func publish(snapshot: DeviceSnapshot, days: [DayReport]) async {
        await start()
        let changes = store.setOwn(snapshot: snapshot, days: days)
        guard let engine, !(changes.save.isEmpty && changes.delete.isEmpty) else { return }
        engine.state.add(pendingRecordZoneChanges:
            changes.save.map { .saveRecord(SyncRecords.recordID($0)) } +
            changes.delete.map { .deleteRecord(SyncRecords.recordID($0)) })
    }

    /// Sends what is pending and fetches what the other devices changed.
    /// The engine also does this on its own; this is for "now".
    public func syncNow() async {
        await start()
        guard entitled, let engine else { return }
        do {
            try await engine.sendChanges()
            try await engine.fetchChanges()
            store.setStatus { $0.lastError = nil }
        } catch {
            syncLog.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            store.setStatus { $0.lastError = Self.describe(error) }
        }
    }

    public func refreshAccount() async {
        guard entitled else {
            store.setStatus { $0.account = .notInThisBuild }
            return
        }
        let account: SyncStatus.Account
        do {
            switch try await container.accountStatus() {
            case .available: account = .available
            case .noAccount: account = .noAccount
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            default: account = .unknown
            }
        } catch {
            account = .unknown
        }
        store.setStatus { $0.account = account }
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            let data = try? JSONEncoder().encode(update.stateSerialization)
            store.update { $0.engineState = data }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                // Everything this device owns goes up to the new account.
                store.update { $0.systemFields = [:]; $0.zoneReady = false }
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
                syncEngine.state.add(pendingRecordZoneChanges: store.allOwnRecordNames.map { .saveRecord(SyncRecords.recordID($0)) })
            case .signOut, .switchAccounts:
                // Another account's devices are not ours to show.
                store.update { $0.remote = [:]; $0.systemFields = [:]; $0.zoneReady = false }
            @unknown default:
                break
            }
            await refreshAccount()

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == SyncRecords.zoneID }) {
                // The zone was deleted (the user cleared iCloud data): start over.
                store.update { $0.remote = [:]; $0.systemFields = [:]; $0.zoneReady = false }
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
                syncEngine.state.add(pendingRecordZoneChanges: store.allOwnRecordNames.map { .saveRecord(SyncRecords.recordID($0)) })
            }

        case .fetchedRecordZoneChanges(let changes):
            let own = store.deviceID
            store.update { file in
                for modification in changes.modifications {
                    let record = modification.record
                    guard let item = SyncRecords.item(from: record) else { continue }
                    switch item {
                    case .device(let snapshot) where snapshot.deviceID == own:
                        file.systemFields[record.recordID.recordName] = SyncRecords.encodeSystemFields(of: record)
                    case .device(let snapshot):
                        var device = file.remote[snapshot.deviceID] ?? RemoteDevice(snapshot: snapshot)
                        if snapshot.updatedAt >= device.snapshot.updatedAt { device.snapshot = snapshot }
                        file.remote[snapshot.deviceID] = device
                    case .day(let report) where report.deviceID == own:
                        file.systemFields[record.recordID.recordName] = SyncRecords.encodeSystemFields(of: record)
                    case .day(let report):
                        var device = file.remote[report.deviceID]
                            ?? RemoteDevice(snapshot: DeviceSnapshot(deviceID: report.deviceID, name: "Device", platform: .mac, updatedAt: .distantPast))
                        if (device.days[report.day]?.updatedAt ?? .distantPast) <= report.updatedAt { device.days[report.day] = report }
                        file.remote[report.deviceID] = device
                    }
                }
                for deletion in changes.deletions {
                    switch SyncRecordName.parse(deletion.recordID.recordName) {
                    case .device(let id)? where id != own: file.remote[id] = nil
                    case .day(let device, let day)? where device != own: file.remote[device]?.days[day] = nil
                    default: file.systemFields[deletion.recordID.recordName] = nil
                    }
                }
            }

        case .sentDatabaseChanges(let changes):
            if changes.savedZones.contains(where: { $0.zoneID == SyncRecords.zoneID }) {
                store.update { $0.zoneReady = true }
            }
            for failure in changes.failedZoneSaves {
                syncLog.error("Zone save failed: \(failure.error.localizedDescription, privacy: .public)")
                store.setStatus { $0.lastError = Self.describe(failure.error) }
            }

        case .sentRecordZoneChanges(let changes):
            store.update { file in
                for record in changes.savedRecords {
                    file.systemFields[record.recordID.recordName] = SyncRecords.encodeSystemFields(of: record)
                }
                for id in changes.deletedRecordIDs { file.systemFields[id.recordName] = nil }
            }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            var needsZone = false
            for failure in changes.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    // Only this device writes its records, so ours wins: take
                    // the server's change tag and send again.
                    if let server = failure.error.serverRecord {
                        store.update { $0.systemFields[id.recordName] = SyncRecords.encodeSystemFields(of: server) }
                    }
                    retry.append(.saveRecord(id))
                case .zoneNotFound, .userDeletedZone:
                    needsZone = true
                    store.update { $0.systemFields[id.recordName] = nil; $0.zoneReady = false }
                    retry.append(.saveRecord(id))
                case .unknownItem:
                    store.update { $0.systemFields[id.recordName] = nil }
                    retry.append(.saveRecord(id))
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited, .notAuthenticated, .accountTemporarilyUnavailable:
                    // The engine retries these on its own.
                    break
                default:
                    syncLog.error("Save \(id.recordName, privacy: .public) failed: \(failure.error.localizedDescription, privacy: .public)")
                    store.setStatus { $0.lastError = Self.describe(failure.error) }
                }
            }
            if needsZone { syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))]) }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
            if !changes.savedRecords.isEmpty || !changes.deletedRecordIDs.isEmpty {
                store.setStatus { $0.lastSentAt = Date(); $0.lastError = nil }
            }

        case .didFetchChanges:
            store.setStatus { $0.lastFetchedAt = Date() }

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let store = self.store
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            let file = store.snapshot
            let item: SyncRecords.Item?
            switch SyncRecordName.parse(recordID.recordName) {
            case .device(let id)? where id == file.deviceID: item = file.ownSnapshot.map(SyncRecords.Item.device)
            case .day(let device, let day)? where device == file.deviceID: item = file.ownDays[day].map(SyncRecords.Item.day)
            default: item = nil
            }
            guard let item, let record = SyncRecords.record(for: item, systemFields: file.systemFields[recordID.recordName]) else {
                // Gone since it was queued (or not ours): nothing to send.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            return record
        }
    }

    // MARK: -

    static func describe(_ error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "not signed in to iCloud."
        case .quotaExceeded: return "your iCloud storage is full."
        case .networkUnavailable, .networkFailure: return "no internet connection."
        case .permissionFailure, .badContainer, .missingEntitlement: return "this build isn't allowed to use iCloud (signing)."
        default: return error.localizedDescription
        }
    }
}
