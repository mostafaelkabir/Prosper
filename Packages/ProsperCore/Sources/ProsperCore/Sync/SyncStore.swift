import Foundation

/// The sync's local state in one file: this device's own records (what it
/// publishes), what it knows about the other devices, CloudKit's bookkeeping
/// (engine state, record system fields) and the status line. On the Mac the
/// agent is the only writer and the app only reads; on the iPhone the app
/// owns it.
public struct SyncFile: Codable, Equatable, Sendable {
    public var deviceID: String
    public var ownSnapshot: DeviceSnapshot?
    public var ownDays: [String: DayReport]
    public var remote: [String: RemoteDevice]
    public var status: SyncStatus
    /// `CKSyncEngine.State.Serialization`, archived.
    public var engineState: Data?
    /// Archived `CKRecord` system fields by record name, so a save carries the
    /// server's change tag instead of colliding with it.
    public var systemFields: [String: Data]
    public var zoneReady: Bool
    /// Archived `CKServerChangeToken` for our own fetch of the zone.
    public var zoneToken: Data?

    public init(deviceID: String) {
        self.deviceID = deviceID
        ownSnapshot = nil
        ownDays = [:]
        remote = [:]
        status = SyncStatus()
        engineState = nil
        systemFields = [:]
        zoneReady = false
        zoneToken = nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        ownSnapshot = try? c.decode(DeviceSnapshot.self, forKey: .ownSnapshot)
        ownDays = (try? c.decode([String: DayReport].self, forKey: .ownDays)) ?? [:]
        remote = (try? c.decode([String: RemoteDevice].self, forKey: .remote)) ?? [:]
        status = (try? c.decode(SyncStatus.self, forKey: .status)) ?? SyncStatus()
        engineState = try? c.decode(Data.self, forKey: .engineState)
        systemFields = (try? c.decode([String: Data].self, forKey: .systemFields)) ?? [:]
        zoneReady = (try? c.decode(Bool.self, forKey: .zoneReady)) ?? false
        zoneToken = try? c.decode(Data.self, forKey: .zoneToken)
    }

    /// Other devices, most recently heard from first. A reinstalled app is a
    /// new device ID with the same name, so only the freshest device per
    /// platform and name is shown, and nothing silent for 30 days.
    public var devices: [RemoteDevice] {
        let cutoff = Date().addingTimeInterval(-Double(SyncStore.retentionDays) * 86_400)
        var seen = Set<String>()
        return remote.values
            .filter { $0.snapshot.updatedAt > cutoff }
            .sorted { $0.snapshot.updatedAt > $1.snapshot.updatedAt }
            .filter { seen.insert("\($0.snapshot.platform.rawValue)|\($0.snapshot.name)").inserted }
    }
}

/// Thread-safe owner of a `SyncFile` on disk.
public final class SyncStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var file: SyncFile

    /// Days a device keeps its own reports in iCloud.
    public static let retentionDays = 30

    public init(url: URL, deviceID: String) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let loaded = try? Self.decoder.decode(SyncFile.self, from: data),
           loaded.deviceID == deviceID {
            file = loaded
        } else {
            file = SyncFile(deviceID: deviceID)
        }
    }

    /// Reads a store file without owning it (the Mac app reading the agent's).
    public static func read(_ url: URL) -> SyncFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SyncFile.self, from: data)
    }

    public var snapshot: SyncFile {
        lock.lock(); defer { lock.unlock() }
        return file
    }

    public var deviceID: String { snapshot.deviceID }

    /// Changes the file and writes it. Returns what the change returned.
    @discardableResult
    public func update<T>(_ change: (inout SyncFile) -> T) -> T {
        lock.lock()
        let result = change(&file)
        let copy = file
        lock.unlock()
        save(copy)
        return result
    }

    private func save(_ copy: SyncFile) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(copy).write(to: url, options: .atomic)
        } catch {
            // A failed save loses at most this change; the next one rewrites
            // the whole file.
        }
    }

    // MARK: - Own records

    /// Record names whose content changed and must be sent. Timestamps alone
    /// do not count, so publishing the same state every few minutes costs
    /// nothing.
    public func setOwn(snapshot: DeviceSnapshot, days: [DayReport], now: Date = Date(), calendar: Calendar = .current) -> (save: [String], delete: [String]) {
        update { file in
            var save: [String] = []
            if file.ownSnapshot?.content != snapshot.content {
                file.ownSnapshot = snapshot
                save.append(SyncRecordName.device(snapshot.deviceID))
            } else if let existing = file.ownSnapshot, now.timeIntervalSince(existing.updatedAt) > 15 * 60 {
                // A heartbeat every 15 minutes, so "last seen" stays honest.
                file.ownSnapshot = snapshot
                save.append(SyncRecordName.device(snapshot.deviceID))
            }
            for day in days where file.ownDays[day.day]?.content != day.content {
                file.ownDays[day.day] = day
                save.append(SyncRecordName.day(device: day.deviceID, day: day.day))
            }
            let cutoff = DayReport.key(for: calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) ?? now, calendar: calendar)
            var delete: [String] = []
            for key in file.ownDays.keys where key < cutoff {
                file.ownDays[key] = nil
                delete.append(SyncRecordName.day(device: file.deviceID, day: key))
            }
            for (key, device) in file.remote {
                file.remote[key]?.days = device.days.filter { $0.key >= cutoff }
            }
            return (save, delete)
        }
    }

    /// Every record this device owns, for a re-upload after an account change.
    public var allOwnRecordNames: [String] {
        let f = snapshot
        var names = f.ownDays.keys.map { SyncRecordName.day(device: f.deviceID, day: $0) }
        if f.ownSnapshot != nil { names.append(SyncRecordName.device(f.deviceID)) }
        return names
    }

    // MARK: - Status

    public func setStatus(_ change: (inout SyncStatus) -> Void) {
        update { change(&$0.status) }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Record names: one snapshot per device, one report per device per day.
public enum SyncRecordName {
    public static func device(_ deviceID: String) -> String { "device.\(deviceID)" }
    public static func day(device: String, day: String) -> String { "day.\(device).\(day)" }

    public enum Parsed: Equatable {
        case device(String)
        case day(device: String, day: String)
    }

    public static func parse(_ name: String) -> Parsed? {
        let parts = name.split(separator: ".", maxSplits: 2).map(String.init)
        switch parts.first {
        case "device" where parts.count >= 2: return .device(parts.dropFirst().joined(separator: "."))
        case "day" where parts.count == 3: return .day(device: parts[1], day: parts[2])
        default: return nil
        }
    }
}
