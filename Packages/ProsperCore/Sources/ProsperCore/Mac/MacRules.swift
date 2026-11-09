import Foundation

/// Everything the Mac enforces, as one versioned document (PLAN.md §3.2).
///
/// The app writes it through `RulesBook`'s add-only operations, the agent keeps
/// it, and the system extension holds its own copy. Every copy is combined with
/// `merged(with:at:)`, which is where the two product promises live in code:
///
/// - a lock can be added to but never shortened, removed or ended early;
/// - the Adult Content Guard can be added to but never shrunk or switched off.
///
/// There is deliberately no operation for the forbidden changes. Merging a copy
/// that has been edited by hand to drop a lock or the guard brings them back.
public struct MacRules: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Bumped on every change, so readers can tell which copy is newer.
    public var revision: Int
    public var sessions: [MacLockSession]
    public var schedules: [MacSchedule]
    /// Schedules removed while their window was closed (the iOS rule, E3.6).
    /// Kept so a stale copy merging in does not resurrect them.
    public var removedScheduleIDs: [UUID]
    /// Nil until the guard is switched on, and never nil again.
    public var guardState: MacGuardState?

    public init(
        version: Int = MacRules.currentVersion,
        revision: Int = 0,
        sessions: [MacLockSession] = [],
        schedules: [MacSchedule] = [],
        removedScheduleIDs: [UUID] = [],
        guardState: MacGuardState? = nil
    ) {
        self.version = version
        self.revision = revision
        self.sessions = sessions
        self.schedules = schedules
        self.removedScheduleIDs = removedScheduleIDs
        self.guardState = guardState
    }

    public static let empty = MacRules()
}

/// One timed lock. Ends at `endsAt`; nothing ends it earlier.
public struct MacLockSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endsAt: Date
    /// Bare registrable domains (`BlockDomain.normalize`), matched with their subdomains.
    public var domains: [String]
    /// Mac apps by bundle identifier.
    public var bundleIDs: [String]
    /// Catalog platforms (`PlatformCatalog`); their domains are blocked too.
    public var platformIDs: [String]
    /// Display names for `bundleIDs`, so the shield and lists can name an app
    /// that is no longer installed.
    public var appNames: [String: String]

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endsAt: Date,
        domains: [String] = [],
        bundleIDs: [String] = [],
        platformIDs: [String] = [],
        appNames: [String: String] = [:]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.domains = domains
        self.bundleIDs = bundleIDs
        self.platformIDs = platformIDs
        self.appNames = appNames
    }

    public func isActive(at date: Date) -> Bool { date >= startedAt && date < endsAt }

    /// Every domain this lock blocks, platforms expanded.
    public var allDomains: Set<String> { MacRules.expand(domains: domains, platformIDs: platformIDs) }
}

/// A lock that switches itself on at set times (E3.6 parity).
public struct MacSchedule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var window: ScheduleWindow
    public var domains: [String]
    public var bundleIDs: [String]
    public var platformIDs: [String]
    public var appNames: [String: String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        window: ScheduleWindow,
        domains: [String] = [],
        bundleIDs: [String] = [],
        platformIDs: [String] = [],
        appNames: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.window = window
        self.domains = domains
        self.bundleIDs = bundleIDs
        self.platformIDs = platformIDs
        self.appNames = appNames
        self.createdAt = createdAt
    }

    public var allDomains: Set<String> { MacRules.expand(domains: domains, platformIDs: platformIDs) }
}

/// The Mac Adult Content Guard (E9 rules). No disable, no clear: every field
/// only grows, and `enabledAt` is never unset.
public struct MacGuardState: Codable, Equatable, Sendable {
    public var enabledAt: Date
    public var domainListVersion: Int
    /// Sites the user added by name. Append-only.
    public var extraDomains: [String]
    /// Apps the user put behind the guard. Append-only.
    public var bundleIDs: [String]
    public var appNames: [String: String]
    /// Search engines and YouTube are forced into their safe modes by the DNS proxy.
    public var safeSearch: Bool
    /// QUIC, encrypted DNS and Private Relay are closed so every flow can be named (§3.4).
    public var closeBypasses: Bool

    public init(
        enabledAt: Date,
        domainListVersion: Int = AdultDomains.macListVersion,
        extraDomains: [String] = [],
        bundleIDs: [String] = [],
        appNames: [String: String] = [:],
        safeSearch: Bool = true,
        closeBypasses: Bool = true
    ) {
        self.enabledAt = enabledAt
        self.domainListVersion = domainListVersion
        self.extraDomains = extraDomains
        self.bundleIDs = bundleIDs
        self.appNames = appNames
        self.safeSearch = safeSearch
        self.closeBypasses = closeBypasses
    }
}

// MARK: - Merging (the invariants)

public extension MacRules {
    /// Combines two copies so that nothing either of them locks is lost.
    ///
    /// - Sessions: union by id; the later end wins; covered items are unioned.
    ///   Sessions whose end has passed are dropped, which is the only way one
    ///   ever leaves the document.
    /// - Schedules: union by id with items unioned. A removal is honoured only
    ///   while that schedule's window is closed at `now`.
    /// - Guard: the earliest switch-on wins; lists are unioned; safety flags
    ///   that are on stay on.
    func merged(with other: MacRules, at now: Date, calendar: Calendar = .current) -> MacRules {
        var result = MacRules(
            version: max(version, other.version),
            revision: max(revision, other.revision)
        )

        var sessionsByID: [UUID: MacLockSession] = [:]
        for session in sessions + other.sessions {
            if let existing = sessionsByID[session.id] {
                sessionsByID[session.id] = existing.union(session)
            } else {
                sessionsByID[session.id] = session
            }
        }
        result.sessions = sessionsByID.values
            .filter { $0.endsAt > now }
            .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }

        var schedulesByID: [UUID: MacSchedule] = [:]
        for schedule in schedules + other.schedules {
            if let existing = schedulesByID[schedule.id] {
                schedulesByID[schedule.id] = existing.union(schedule)
            } else {
                schedulesByID[schedule.id] = schedule
            }
        }
        var removed = Set(removedScheduleIDs).union(other.removedScheduleIDs)
        // A schedule whose window is open right now cannot be removed, whoever asks.
        for id in removed {
            if let schedule = schedulesByID[id], schedule.window.contains(now, calendar: calendar) {
                removed.remove(id)
            }
        }
        result.schedules = schedulesByID.values
            .filter { !removed.contains($0.id) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        result.removedScheduleIDs = removed.sorted { $0.uuidString < $1.uuidString }

        switch (guardState, other.guardState) {
        case let (a?, b?): result.guardState = a.union(b)
        case let (a?, nil): result.guardState = a
        case let (nil, b?): result.guardState = b
        case (nil, nil): result.guardState = nil
        }
        return result
    }

    /// True when `newer` keeps everything `self` locks at `now`: no active
    /// session ends sooner or covers less, no open schedule is gone or covers
    /// less, and the guard is neither gone nor smaller. Used by tests and by the
    /// extension to log tampering.
    func isPreserved(by newer: MacRules, at now: Date, calendar: Calendar = .current) -> Bool {
        for session in sessions where session.endsAt > now {
            guard let kept = newer.sessions.first(where: { $0.id == session.id }),
                  kept.endsAt >= session.endsAt,
                  Set(kept.domains).isSuperset(of: session.domains),
                  Set(kept.bundleIDs).isSuperset(of: session.bundleIDs),
                  Set(kept.platformIDs).isSuperset(of: session.platformIDs) else { return false }
        }
        for schedule in schedules where schedule.window.contains(now, calendar: calendar) {
            guard let kept = newer.schedules.first(where: { $0.id == schedule.id }),
                  Set(kept.domains).isSuperset(of: schedule.domains),
                  Set(kept.bundleIDs).isSuperset(of: schedule.bundleIDs),
                  Set(kept.platformIDs).isSuperset(of: schedule.platformIDs) else { return false }
        }
        if let guardState {
            guard let kept = newer.guardState,
                  kept.enabledAt <= guardState.enabledAt,
                  Set(kept.extraDomains).isSuperset(of: guardState.extraDomains),
                  Set(kept.bundleIDs).isSuperset(of: guardState.bundleIDs),
                  kept.safeSearch || !guardState.safeSearch,
                  kept.closeBypasses || !guardState.closeBypasses else { return false }
        }
        return true
    }

    static func expand(domains: [String], platformIDs: [String]) -> Set<String> {
        var all = Set(domains.map { $0.lowercased() })
        for id in platformIDs {
            if let platform = PlatformCatalog.platform(id: id) {
                all.formUnion(platform.domains.map { $0.lowercased() })
            }
        }
        return all
    }
}

private func unionOrdered(_ a: [String], _ b: [String]) -> [String] {
    var seen = Set<String>()
    return (a + b).filter { seen.insert($0).inserted }
}

extension MacLockSession {
    func union(_ other: MacLockSession) -> MacLockSession {
        var result = self
        result.startedAt = min(startedAt, other.startedAt)
        result.endsAt = max(endsAt, other.endsAt)
        result.domains = unionOrdered(domains, other.domains)
        result.bundleIDs = unionOrdered(bundleIDs, other.bundleIDs)
        result.platformIDs = unionOrdered(platformIDs, other.platformIDs)
        result.appNames = appNames.merging(other.appNames) { a, _ in a }
        return result
    }
}

extension MacSchedule {
    func union(_ other: MacSchedule) -> MacSchedule {
        var result = self
        result.domains = unionOrdered(domains, other.domains)
        result.bundleIDs = unionOrdered(bundleIDs, other.bundleIDs)
        result.platformIDs = unionOrdered(platformIDs, other.platformIDs)
        result.appNames = appNames.merging(other.appNames) { a, _ in a }
        result.createdAt = min(createdAt, other.createdAt)
        return result
    }
}

extension MacGuardState {
    func union(_ other: MacGuardState) -> MacGuardState {
        MacGuardState(
            enabledAt: min(enabledAt, other.enabledAt),
            domainListVersion: max(domainListVersion, other.domainListVersion),
            extraDomains: unionOrdered(extraDomains, other.extraDomains),
            bundleIDs: unionOrdered(bundleIDs, other.bundleIDs),
            appNames: appNames.merging(other.appNames) { a, _ in a },
            safeSearch: safeSearch || other.safeSearch,
            closeBypasses: closeBypasses || other.closeBypasses
        )
    }
}
