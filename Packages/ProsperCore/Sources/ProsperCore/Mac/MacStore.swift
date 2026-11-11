import Foundation

/// Where the Mac app and agent keep their shared files: one folder in the
/// user's Application Support, written atomically as JSON. Both processes run
/// as the user and are not sandboxed, so a plain folder is the simplest thing
/// that is always the same path for both. The system extension runs as root in
/// its own sandbox and never reads this folder: it gets its rules over XPC.
public enum MacStore {
    public static let folderName = "StolenEyes"

    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var rulesURL: URL { directory.appendingPathComponent("rules.json") }
    public static var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    public static var statusURL: URL { directory.appendingPathComponent("agent-status.json") }
    public static var eventsURL: URL { directory.appendingPathComponent("events.json") }
    /// Connected devices (M7): the agent's sync state and what it knows about
    /// the user's other devices. The agent writes it; the app only reads it.
    public static var syncURL: URL { directory.appendingPathComponent("sync.json") }
    /// Touched by the app to ask the agent to sync now.
    public static var syncRequestURL: URL { directory.appendingPathComponent("sync-request") }

    /// This Mac's ID among the user's devices: made once, kept in the folder
    /// so reinstalling the app does not make it a new device.
    public static var deviceID: String {
        let url = directory.appendingPathComponent("device-id")
        if let text = try? String(contentsOf: url, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = UUID().uuidString
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }
    public static var usageDirectory: URL {
        let url = directory.appendingPathComponent("usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func usageURL(for day: String) -> URL { usageDirectory.appendingPathComponent(day + ".json") }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Rules

    /// The rules as the user's folder has them now, merged add-only with
    /// `known` so a hand-edited file cannot drop a lock or the guard.
    public static func loadRules(mergingWith known: MacRules? = nil, at now: Date = Date()) -> MacRules {
        let onDisk = read(MacRules.self, from: rulesURL) ?? .empty
        guard let known else { return onDisk.merged(with: .empty, at: now) }
        return onDisk.merged(with: known, at: now)
    }

    /// Applies one `RulesBook` operation to the latest rules and saves the
    /// result. The read-modify-write is guarded by a lock file so the app and
    /// the agent never interleave.
    @discardableResult
    public static func updateRules(at now: Date = Date(), _ change: (MacRules) throws -> MacRules) throws -> MacRules {
        try withLock {
            let current = loadRules(at: now)
            var next = try change(current)
            // Whatever the change did, it cannot take anything away.
            next = next.merged(with: current, at: now)
            try write(next, to: rulesURL)
            return next
        }
    }

    public static func loadSettings() -> MacSettings { read(MacSettings.self, from: settingsURL) ?? MacSettings() }

    public static func updateSettings(_ change: (inout MacSettings) -> Void) {
        try? withLock {
            var settings = loadSettings()
            change(&settings)
            try write(settings, to: settingsURL)
        }
    }

    public static func loadDay(_ day: String) -> UsageDay? { read(UsageDay.self, from: usageURL(for: day)) }

    public static func loadDays(endingAt date: Date = Date(), count: Int, calendar: Calendar = .current) -> [UsageDay] {
        (0..<count).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return loadDay(UsageDay.key(for: d, calendar: calendar))
        }
    }

    private static func withLock<T>(_ body: () throws -> T) throws -> T {
        let lockURL = directory.appendingPathComponent(".lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

/// What the agent reports about itself and the filter, refreshed every few
/// seconds. The app shows any gap in red rather than assuming (PLAN.md §7.4).
public struct AgentStatus: Codable, Equatable, Sendable {
    public var heartbeat: Date
    public var agentStartedAt: Date
    public var agentVersion: String
    public var filter: FilterStatus?
    public var filterError: String?
    /// Browsers the agent could read the address bar of, by bundle ID → true / false (Automation refused).
    public var browserAccess: [String: Bool]
    public var screenGuard: ScreenGuardStatus

    public init(heartbeat: Date, agentStartedAt: Date, agentVersion: String, filter: FilterStatus? = nil, filterError: String? = nil, browserAccess: [String: Bool] = [:], screenGuard: ScreenGuardStatus = .off) {
        self.heartbeat = heartbeat
        self.agentStartedAt = agentStartedAt
        self.agentVersion = agentVersion
        self.filter = filter
        self.filterError = filterError
        self.browserAccess = browserAccess
        self.screenGuard = screenGuard
    }

    public func isFresh(at now: Date = Date()) -> Bool { now.timeIntervalSince(heartbeat) < 20 }
}

public enum ScreenGuardStatus: String, Codable, Sendable {
    case off, running, needsScreenRecording, sensitiveContentWarningOff, unavailable
}

/// The system extension's own account of itself, returned over XPC.
public struct FilterStatus: Codable, Equatable, Sendable {
    public var filterStartedAt: Date?
    public var dnsStartedAt: Date?
    public var rulesRevision: Int
    public var guardOn: Bool
    public var activeLocks: Int
    public var blockedToday: Int
    public var unnamedToday: Int
    public var safeSearchRewritesToday: Int
    public var day: String

    public init(filterStartedAt: Date? = nil, dnsStartedAt: Date? = nil, rulesRevision: Int = 0, guardOn: Bool = false, activeLocks: Int = 0, blockedToday: Int = 0, unnamedToday: Int = 0, safeSearchRewritesToday: Int = 0, day: String = "") {
        self.filterStartedAt = filterStartedAt
        self.dnsStartedAt = dnsStartedAt
        self.rulesRevision = rulesRevision
        self.guardOn = guardOn
        self.activeLocks = activeLocks
        self.blockedToday = blockedToday
        self.unnamedToday = unnamedToday
        self.safeSearchRewritesToday = safeSearchRewritesToday
        self.day = day
    }
}

/// A moment worth keeping: a blocked app opened, a guard hit, a gap in
/// protection. Never pixels, never page addresses (PLAN.md §7.7).
public struct MacEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case appBlocked, siteBlocked, guardSite, guardScreen, guardApp, agentStarted }
    public var id: UUID
    public var at: Date
    public var kind: Kind
    public var subject: String

    public init(id: UUID = UUID(), at: Date = Date(), kind: Kind, subject: String) {
        self.id = id
        self.at = at
        self.kind = kind
        self.subject = subject
    }
}
