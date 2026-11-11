import Foundation

/// Why a host or app is blocked right now.
public enum BlockReason: Equatable, Sendable {
    case adultGuard
    case session(endsAt: Date)
    case schedule(name: String, endsAt: Date)

    public var endsAt: Date? {
        switch self {
        case .adultGuard: nil
        case .session(let endsAt), .schedule(_, let endsAt): endsAt
        }
    }
}

/// The rules in force at one moment, compiled for fast lookups. The extension
/// and the agent rebuild this every time the rules change and once a minute,
/// so a session that ends lifts within a minute (SC2).
public struct ActiveRules: Sendable {
    public let builtAt: Date
    /// Sites blocked by a session or schedule, with the latest end among the locks covering each.
    private let lockedDomains: DomainMatcher
    private let lockedDomainEnds: [String: BlockReason]
    public let lockedBundleIDs: [String: BlockReason]
    public let guardOn: Bool
    public let guardBundleIDs: Set<String>
    private let guardDomains: DomainMatcher
    public let safeSearch: Bool
    public let closeBypasses: Bool
    /// Earliest moment the result can change (a lock ending or a schedule opening/closing).
    public let validUntil: Date

    public init(rules: MacRules, at now: Date, calendar: Calendar = .current) {
        builtAt = now
        var domainReasons: [String: BlockReason] = [:]
        var bundleReasons: [String: BlockReason] = [:]
        var nextChange = now.addingTimeInterval(60)

        func record(_ reason: BlockReason, domains: Set<String>, bundleIDs: [String]) {
            for domain in domains { domainReasons[domain] = Self.later(domainReasons[domain], reason) }
            for id in bundleIDs { bundleReasons[id] = Self.later(bundleReasons[id], reason) }
        }

        for session in rules.sessions where session.isActive(at: now) {
            record(.session(endsAt: session.endsAt), domains: session.allDomains, bundleIDs: session.bundleIDs)
            nextChange = min(nextChange, session.endsAt)
        }
        for session in rules.sessions where session.startedAt > now {
            nextChange = min(nextChange, session.startedAt)
        }
        for schedule in rules.schedules {
            if let open = schedule.window.interval(containing: now, calendar: calendar) {
                record(.schedule(name: schedule.name, endsAt: open.end), domains: schedule.allDomains, bundleIDs: schedule.bundleIDs)
                nextChange = min(nextChange, open.end)
            }
        }
        lockedDomainEnds = domainReasons
        lockedDomains = DomainMatcher(domainReasons.keys)
        lockedBundleIDs = bundleReasons

        if let state = rules.guardState {
            guardOn = true
            guardBundleIDs = Set(state.bundleIDs)
            guardDomains = DomainMatcher(AdultDomains.mac.union(state.extraDomains))
            safeSearch = state.safeSearch
            closeBypasses = state.closeBypasses
        } else {
            guardOn = false
            guardBundleIDs = []
            guardDomains = DomainMatcher([])
            safeSearch = false
            closeBypasses = false
        }
        validUntil = nextChange
    }

    /// Why `host` is blocked, or nil. The guard is checked first: its block has no end.
    public func reason(forHost host: String) -> BlockReason? {
        let host = Self.clean(host)
        guard !host.isEmpty else { return nil }
        if guardOn, guardDomains.matchedDomain(host) != nil || GuardMatcher.looksAdult(host) {
            return .adultGuard
        }
        if let domain = lockedDomains.matchedDomain(host) {
            return lockedDomainEnds[domain]
        }
        return nil
    }

    public func reason(forBundleID bundleID: String) -> BlockReason? {
        if guardOn, guardBundleIDs.contains(bundleID) { return .adultGuard }
        return lockedBundleIDs[bundleID]
    }

    public var hasLocks: Bool { !lockedDomainEnds.isEmpty || !lockedBundleIDs.isEmpty }
    public var lockedDomainCount: Int { lockedDomainEnds.count }

    /// Lower-case, no trailing dot, no "www.".
    static func clean(_ host: String) -> String {
        var h = host.lowercased()
        while h.hasSuffix(".") { h.removeLast() }
        return h
    }

    private static func later(_ a: BlockReason?, _ b: BlockReason) -> BlockReason {
        guard let a else { return b }
        switch (a.endsAt, b.endsAt) {
        case (nil, _): return a
        case (_, nil): return b
        case let (x?, y?): return y > x ? b : a
        }
    }
}

/// Suffix matching on whole labels: `m.youtube.com` matches `youtube.com`,
/// `notyoutube.com` does not.
public struct DomainMatcher: Sendable {
    private let domains: Set<String>

    public init<S: Sequence>(_ domains: S) where S.Element == String {
        self.domains = Set(domains.map { ActiveRules.clean($0) }.filter { !$0.isEmpty })
    }

    public var isEmpty: Bool { domains.isEmpty }

    /// The listed domain `host` falls under, or nil.
    public func matchedDomain(_ host: String) -> String? {
        guard !domains.isEmpty else { return nil }
        var candidate = Substring(ActiveRules.clean(host))
        while true {
            if domains.contains(String(candidate)) { return String(candidate) }
            guard let dot = candidate.firstIndex(of: ".") else { return nil }
            candidate = candidate[candidate.index(after: dot)...]
        }
    }
}

/// Recognises adult hosts that are not on any list, by their names. Strong
/// words match anywhere in the host; the rest only as a whole label or at the
/// start or end of a label, so "essex.ac.uk", "sussex.com" and "sextant.io" stay
/// reachable while "freeporn.example" and "nudes-archive.net" do not.
public enum GuardMatcher {
    /// Words with no innocent use, matched anywhere: "freeporn", "ixxx".
    static let anywhere: [String] = ["porn", "xxx", "hentai"]
    /// Site names, matched where a name part starts ("xvideos2.com",
    /// "de.xvideos.com"), never inside another word: Netflix's video CDN is
    /// nfl-xvideo-.net, and matching it anywhere broke Netflix and fast.com
    /// on every guarded Mac (QA-11).
    static let brands: [String] = ["xvideo", "xnxx", "xhamster", "redtube", "youporn", "brazzers", "onlyfans", "rule34"]

    public static func looksAdult(_ host: String) -> Bool {
        let host = ActiveRules.clean(host)
        if anywhere.contains(where: { host.contains($0) }) { return true }
        let tokens = host.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "_" }).map(String.init)
        if tokens.contains(where: { token in brands.contains { token.hasPrefix($0) } }) { return true }
        // The last label is the TLD (.xxx is caught above; .sex, .porn, .adult here).
        if let tld = tokens.last, ["sex", "porn", "adult", "xxx", "sexy"].contains(tld), tokens.count > 1 { return true }
        for token in tokens.dropLast() {
            for word in AdultDomains.hostKeywords where !brands.contains(word) && (token == word || (word.count >= 4 && (token.hasPrefix(word) || token.hasSuffix(word)))) {
                if allowedTokens.contains(token) { continue }
                return true
            }
        }
        return false
    }

    /// Ordinary words that begin or end with a keyword.
    static let allowedTokens: Set<String> = [
        "nudge", "nudges", "escorted", "fetishism", "eroticism", "pornography",
        "milford", "milfordschool", "escortcar",
    ]
}
