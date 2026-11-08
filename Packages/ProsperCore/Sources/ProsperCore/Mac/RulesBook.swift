import Foundation

/// The only way the Mac changes its rules. Every operation adds; none shortens,
/// removes or ends a lock, and none shrinks or disables the guard. That is the
/// whole API: the forbidden operations do not exist (CLAUDE.md, PLAN.md §7).
///
/// `RulesBookTests` enumerates this type's operations and checks each one
/// preserves the previous rules.
public enum RulesBook {
    public enum EditError: Error, Equatable, LocalizedError {
        case nothingToLock
        case tooShort
        case unknownLock
        case scheduleIsOn(until: Date)

        public var errorDescription: String? {
            switch self {
            case .nothingToLock: "Choose at least one app or site."
            case .tooShort: "A lock lasts at least one minute."
            case .unknownLock: "That lock has already ended."
            case .scheduleIsOn(let until):
                "This schedule is on until \(until.formatted(date: .omitted, time: .shortened)). It can be removed after that."
            }
        }
    }

    /// Starts a new timed lock.
    public static func startingSession(
        _ rules: MacRules,
        minutes: Int,
        domains: [String],
        bundleIDs: [String],
        platformIDs: [String],
        appNames: [String: String] = [:],
        now: Date = Date()
    ) throws -> (MacRules, MacLockSession) {
        guard minutes >= 1 else { throw EditError.tooShort }
        let domains = normalized(domains)
        guard !(domains.isEmpty && bundleIDs.isEmpty && platformIDs.isEmpty) else { throw EditError.nothingToLock }
        let session = MacLockSession(
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
            domains: domains,
            bundleIDs: unique(bundleIDs),
            platformIDs: unique(platformIDs),
            appNames: appNames
        )
        var next = rules
        next.sessions.append(session)
        next.revision += 1
        return (next, session)
    }

    /// Adds apps or sites to a running lock (UX-25 parity). Add-only.
    public static func adding(
        to sessionID: UUID,
        _ rules: MacRules,
        domains: [String] = [],
        bundleIDs: [String] = [],
        platformIDs: [String] = [],
        appNames: [String: String] = [:],
        now: Date = Date()
    ) throws -> MacRules {
        guard let index = rules.sessions.firstIndex(where: { $0.id == sessionID && $0.endsAt > now }) else {
            throw EditError.unknownLock
        }
        var next = rules
        let addition = MacLockSession(
            id: sessionID,
            startedAt: rules.sessions[index].startedAt,
            endsAt: rules.sessions[index].endsAt,
            domains: normalized(domains),
            bundleIDs: bundleIDs,
            platformIDs: platformIDs,
            appNames: appNames
        )
        next.sessions[index] = rules.sessions[index].union(addition)
        next.revision += 1
        return next
    }

    /// Makes a running lock last longer. A later end only; an earlier one is ignored.
    public static func extending(_ sessionID: UUID, _ rules: MacRules, byMinutes minutes: Int, now: Date = Date()) throws -> MacRules {
        guard minutes > 0 else { throw EditError.tooShort }
        guard let index = rules.sessions.firstIndex(where: { $0.id == sessionID && $0.endsAt > now }) else {
            throw EditError.unknownLock
        }
        var next = rules
        next.sessions[index].endsAt = rules.sessions[index].endsAt.addingTimeInterval(TimeInterval(minutes * 60))
        next.revision += 1
        return next
    }

    public static func addingSchedule(
        _ rules: MacRules,
        name: String,
        window: ScheduleWindow,
        domains: [String],
        bundleIDs: [String],
        platformIDs: [String],
        appNames: [String: String] = [:],
        now: Date = Date()
    ) throws -> (MacRules, MacSchedule) {
        let domains = normalized(domains)
        guard !(domains.isEmpty && bundleIDs.isEmpty && platformIDs.isEmpty) else { throw EditError.nothingToLock }
        guard window.spanMinutes >= 1, !window.weekdays.isEmpty else { throw EditError.tooShort }
        let schedule = MacSchedule(
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Schedule" : name,
            window: window,
            domains: domains,
            bundleIDs: unique(bundleIDs),
            platformIDs: unique(platformIDs),
            appNames: appNames,
            createdAt: now
        )
        var next = rules
        next.schedules.append(schedule)
        next.revision += 1
        return (next, schedule)
    }

    /// Adds to a schedule, even while its window is open (UX-26 parity).
    public static func adding(
        toSchedule scheduleID: UUID,
        _ rules: MacRules,
        domains: [String] = [],
        bundleIDs: [String] = [],
        platformIDs: [String] = [],
        appNames: [String: String] = [:]
    ) throws -> MacRules {
        guard let index = rules.schedules.firstIndex(where: { $0.id == scheduleID }) else { throw EditError.unknownLock }
        var addition = rules.schedules[index]
        addition.domains = normalized(domains)
        addition.bundleIDs = bundleIDs
        addition.platformIDs = platformIDs
        addition.appNames = appNames
        var next = rules
        next.schedules[index] = rules.schedules[index].union(addition)
        next.revision += 1
        return next
    }

    /// Removes a schedule, only while its window is closed: the iPhone's rule.
    /// An open window is a running lock, and running locks do not end early.
    public static func removingSchedule(_ scheduleID: UUID, _ rules: MacRules, now: Date = Date(), calendar: Calendar = .current) throws -> MacRules {
        guard let schedule = rules.schedules.first(where: { $0.id == scheduleID }) else { throw EditError.unknownLock }
        if let open = schedule.window.interval(containing: now, calendar: calendar) {
            throw EditError.scheduleIsOn(until: open.end)
        }
        var next = rules
        next.schedules.removeAll { $0.id == scheduleID }
        if !next.removedScheduleIDs.contains(scheduleID) { next.removedScheduleIDs.append(scheduleID) }
        next.revision += 1
        return next
    }

    /// Switches the Adult Content Guard on. Calling it again changes nothing:
    /// the first date stays.
    public static func enablingGuard(_ rules: MacRules, now: Date = Date()) -> MacRules {
        guard rules.guardState == nil else { return rules }
        var next = rules
        next.guardState = MacGuardState(enabledAt: now)
        next.revision += 1
        return next
    }

    /// Puts more sites or apps behind the guard. Append-only.
    public static func addingToGuard(_ rules: MacRules, domains: [String] = [], bundleIDs: [String] = [], appNames: [String: String] = [:]) -> MacRules {
        guard let current = rules.guardState else { return rules }
        var addition = current
        addition.extraDomains = normalized(domains)
        addition.bundleIDs = bundleIDs
        addition.appNames = appNames
        var next = rules
        next.guardState = current.union(addition)
        next.revision += 1
        return next
    }

    private static func normalized(_ domains: [String]) -> [String] {
        unique(domains.compactMap(BlockDomain.normalize))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
