import Foundation

// What one device tells the others (PLAN.md M7). Each device writes only its
// own records, so there are no conflicts between devices to resolve. Payloads
// are JSON inside the CloudKit record, so fields can be added without a
// CloudKit schema change; every field decodes with a default so an older
// build reading a newer record still works.

public enum DevicePlatform: String, Codable, Sendable {
    case iPhone
    case mac

    public var label: String { self == .mac ? "Mac" : "iPhone" }
}

/// How a device's numbers were measured. The combined views say this out
/// loud: the Mac measures every app and site exactly, the iPhone can only
/// share markers from its waste list (iOS keeps per-app minutes inside the
/// report extension, which cannot send anything anywhere).
public enum MeasurementKind: String, Codable, Sendable {
    case exact
    case wasteMarkers
}

/// The device as it is right now: who it is, and what is locked on it.
public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var platform: DevicePlatform
    public var updatedAt: Date
    public var appVersion: String
    public var guardOn: Bool
    public var guardSince: Date?
    /// The lock running now, if any.
    public var lock: LockSummary?
    public var schedules: [ScheduleSummary]

    public init(deviceID: String, name: String, platform: DevicePlatform, updatedAt: Date = Date(), appVersion: String = "",
                guardOn: Bool = false, guardSince: Date? = nil, lock: LockSummary? = nil, schedules: [ScheduleSummary] = []) {
        self.deviceID = deviceID
        self.name = name
        self.platform = platform
        self.updatedAt = updatedAt
        self.appVersion = appVersion
        self.guardOn = guardOn
        self.guardSince = guardSince
        self.lock = lock
        self.schedules = schedules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Device"
        platform = (try? c.decode(DevicePlatform.self, forKey: .platform)) ?? .mac
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? .distantPast
        appVersion = (try? c.decode(String.self, forKey: .appVersion)) ?? ""
        guardOn = (try? c.decode(Bool.self, forKey: .guardOn)) ?? false
        guardSince = try? c.decode(Date.self, forKey: .guardSince)
        lock = try? c.decode(LockSummary.self, forKey: .lock)
        schedules = (try? c.decode([ScheduleSummary].self, forKey: .schedules)) ?? []
    }

    /// The same snapshot without its timestamp, to tell a real change from a
    /// re-publish of the same state.
    public var content: DeviceSnapshot {
        var copy = self
        copy.updatedAt = .distantPast
        return copy
    }
}

public struct LockSummary: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endsAt: Date
    /// What is locked, in words: "YouTube", "reddit.com", "3 apps".
    public var items: [String]

    public init(startedAt: Date, endsAt: Date, items: [String]) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.items = items
    }
}

public struct ScheduleSummary: Codable, Equatable, Sendable {
    public var name: String
    /// "10:00 PM – 7:00 AM · Every day"
    public var window: String
    public var isOnNow: Bool

    public init(name: String, window: String, isOnNow: Bool) {
        self.name = name
        self.window = window
        self.isOnNow = isOnNow
    }
}

/// One day on one device.
public struct DayReport: Codable, Equatable, Sendable {
    public var deviceID: String
    /// "yyyy-MM-dd" in the device's own calendar.
    public var day: String
    public var updatedAt: Date
    public var measurement: MeasurementKind

    // Exact measurement (Mac).
    public var totalSeconds: Double
    /// Keyed by `TimeClassKind.rawValue`, plus "unclassified".
    public var classSeconds: [String: Double]
    public var hourly: [Double]
    public var hourlyDistracting: [Double]
    public var top: [UsageLine]
    public var unlocks: Int
    public var opens: Int
    public var longestDistractingRun: Double
    public var longestDistractingRunName: String?

    // Waste-list markers (iPhone): the highest marker reached is a floor, not
    // the exact figure.
    public var wasteMarks: [WasteMark]

    // Behaviour, both devices.
    public var warnings: [WarningLine]
    /// Times a locked app or site was opened and refused.
    public var blockedAttempts: Int
    public var locksStarted: [LockLine]

    public init(deviceID: String, day: String, updatedAt: Date = Date(), measurement: MeasurementKind,
                totalSeconds: Double = 0, classSeconds: [String: Double] = [:], hourly: [Double] = [], hourlyDistracting: [Double] = [],
                top: [UsageLine] = [], unlocks: Int = 0, opens: Int = 0, longestDistractingRun: Double = 0, longestDistractingRunName: String? = nil,
                wasteMarks: [WasteMark] = [], warnings: [WarningLine] = [], blockedAttempts: Int = 0, locksStarted: [LockLine] = []) {
        self.deviceID = deviceID
        self.day = day
        self.updatedAt = updatedAt
        self.measurement = measurement
        self.totalSeconds = totalSeconds
        self.classSeconds = classSeconds
        self.hourly = hourly
        self.hourlyDistracting = hourlyDistracting
        self.top = top
        self.unlocks = unlocks
        self.opens = opens
        self.longestDistractingRun = longestDistractingRun
        self.longestDistractingRunName = longestDistractingRunName
        self.wasteMarks = wasteMarks
        self.warnings = warnings
        self.blockedAttempts = blockedAttempts
        self.locksStarted = locksStarted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try c.decode(String.self, forKey: .deviceID)
        day = try c.decode(String.self, forKey: .day)
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? .distantPast
        measurement = (try? c.decode(MeasurementKind.self, forKey: .measurement)) ?? .exact
        totalSeconds = (try? c.decode(Double.self, forKey: .totalSeconds)) ?? 0
        classSeconds = (try? c.decode([String: Double].self, forKey: .classSeconds)) ?? [:]
        hourly = (try? c.decode([Double].self, forKey: .hourly)) ?? []
        hourlyDistracting = (try? c.decode([Double].self, forKey: .hourlyDistracting)) ?? []
        top = (try? c.decode([UsageLine].self, forKey: .top)) ?? []
        unlocks = (try? c.decode(Int.self, forKey: .unlocks)) ?? 0
        opens = (try? c.decode(Int.self, forKey: .opens)) ?? 0
        longestDistractingRun = (try? c.decode(Double.self, forKey: .longestDistractingRun)) ?? 0
        longestDistractingRunName = try? c.decode(String.self, forKey: .longestDistractingRunName)
        wasteMarks = (try? c.decode([WasteMark].self, forKey: .wasteMarks)) ?? []
        warnings = (try? c.decode([WarningLine].self, forKey: .warnings)) ?? []
        blockedAttempts = (try? c.decode(Int.self, forKey: .blockedAttempts)) ?? 0
        locksStarted = (try? c.decode([LockLine].self, forKey: .locksStarted)) ?? []
    }

    public var distractingSeconds: Double { classSeconds[TimeClassKind.distracting.rawValue] ?? 0 }

    /// The highest waste marker reached: at least this much time in the
    /// waste list today.
    public var wasteAtLeastSeconds: Double { Double(wasteMarks.map(\.minutes).max() ?? 0) * 60 }

    /// The same report without its timestamp, to tell a real change from a
    /// re-publish.
    public var content: DayReport {
        var copy = self
        copy.updatedAt = .distantPast
        return copy
    }

    /// "yyyy-MM-dd" for `date` in `calendar`.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public struct UsageLine: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case app, site, platform }
    public var name: String
    public var kind: Kind
    public var seconds: Double
    public var opens: Int
    /// `TimeClassKind.rawValue`, or nil when unlabelled.
    public var timeClass: String?

    public init(name: String, kind: Kind, seconds: Double, opens: Int, timeClass: String?) {
        self.name = name
        self.kind = kind
        self.seconds = seconds
        self.opens = opens
        self.timeClass = timeClass
    }
}

/// "Today's time in the waste list reached `minutes` at `reachedAt`."
public struct WasteMark: Codable, Equatable, Sendable {
    public var minutes: Int
    public var reachedAt: Date

    public init(minutes: Int, reachedAt: Date) {
        self.minutes = minutes
        self.reachedAt = reachedAt
    }
}

public struct WarningLine: Codable, Equatable, Sendable {
    public var level: Int
    public var text: String
    public var at: Date

    public init(level: Int, text: String, at: Date) {
        self.level = level
        self.text = text
        self.at = at
    }
}

public struct LockLine: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endsAt: Date
    public var itemCount: Int

    public init(startedAt: Date, endsAt: Date, itemCount: Int) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.itemCount = itemCount
    }
}

/// Everything known about another device.
public struct RemoteDevice: Codable, Equatable, Sendable, Identifiable {
    public var snapshot: DeviceSnapshot
    /// Keyed by day.
    public var days: [String: DayReport]

    public var id: String { snapshot.deviceID }

    public init(snapshot: DeviceSnapshot, days: [String: DayReport] = [:]) {
        self.snapshot = snapshot
        self.days = days
    }

    public func day(_ date: Date = Date(), calendar: Calendar = .current) -> DayReport? {
        days[DayReport.key(for: date, calendar: calendar)]
    }
}

/// The sync's state, as the UI shows it.
public struct SyncStatus: Codable, Equatable, Sendable {
    public enum Account: String, Codable, Sendable {
        case unknown, available, noAccount, restricted, temporarilyUnavailable
        /// This build was signed without iCloud (a test build, or the Mac
        /// installed without its filter).
        case notInThisBuild
    }
    public var account: Account
    public var lastSentAt: Date?
    public var lastFetchedAt: Date?
    public var lastError: String?

    public init(account: Account = .unknown, lastSentAt: Date? = nil, lastFetchedAt: Date? = nil, lastError: String? = nil) {
        self.account = account
        self.lastSentAt = lastSentAt
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
    }

    /// One sentence for Settings.
    public var summary: String {
        switch account {
        case .noAccount: "Not signed in to iCloud. Sign in with your Apple Account in System Settings (Mac) or Settings (iPhone) to connect your devices."
        case .restricted: "iCloud is restricted on this device (Screen Time or device management), so it can't connect to your other devices."
        case .temporarilyUnavailable: "iCloud is temporarily unavailable. StolenEyes will connect again on its own."
        case .notInThisBuild: "This copy of StolenEyes was built without iCloud, so it can't connect to your other devices. Install the full build to connect them."
        case .unknown: "Checking iCloud…"
        case .available:
            if let lastError { "Connected to iCloud, but the last sync failed: \(lastError)" } else { "Connected through your iCloud account. Only your devices can read this data." }
        }
    }
}
