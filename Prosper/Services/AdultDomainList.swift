import Foundation
import ManagedSettings

/// The websites the Adult Content Guard blocks by name, and how they become a
/// web-content filter policy (E9).
///
/// Apple's automatic adult-content filter (`.auto`) does the heavy lifting: it
/// classifies the long tail of adult sites, and Prosper cannot see or improve
/// its list. The names here sit on top of it for three reasons:
///
/// 1. The highest-traffic sites must be blocked even if the classifier is
///    wrong or late about one of them. A guard that fails on the single site
///    someone actually types is not a guard.
/// 2. Some of the biggest adult destinations have clean-looking landing pages
///    (creator platforms, cam sites, leak archives) and generic filters are
///    known to miss them.
/// 3. The directories and search engines people use to *find* adult sites are
///    the real relapse path once the familiar names are gone. Blocking the
///    index closes the search for a way around, which is where most of the
///    willpower would otherwise be spent.
///
/// The list is deliberately short. Apple documents 50 named domains per
/// policy, but on device the filter has been seen to stop blocking anything
/// once roughly 49 are in play, and every block session and schedule adds its
/// own names on top. Twelve sites that matter most, plus a few the user can
/// add, keeps the guard far from that edge; Apple's classifier does the rest.
enum AdultDomainList {
    /// Apple's web content filter accepts at most this many named domains at
    /// once (same limit as `BlockingService.maxDomains`).
    static let filterCapacity = 50

    /// Blocked by name. Lower-case bare domains, exactly as `BlockDomain.normalize`
    /// would produce them; the unit tests hold that line. Subdomains are
    /// covered by the filter's domain matching.
    /// Shared with the Mac guard, which blocks these and far more
    /// (`AdultDomains.mac`).
    static let builtIn: [String] = AdultDomains.builtIn

    /// Sites the user can add by name. Kept small on purpose: a device report
    /// puts the real, undocumented limit near 49 domains across the filter,
    /// past which it silently blocks nothing (Apple forums thread 730444), and
    /// block sessions and schedules need their share of that budget too.
    static let userSlots = 8

    /// The built-in list plus the user's additions: deduplicated, in order,
    /// and never longer than the guard allows itself.
    static func domains(adding typed: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for domain in builtIn + typed where seen.insert(domain).inserted {
            result.append(domain)
        }
        return Array(result.prefix(builtIn.count + userSlots))
    }

    /// The guard's own policy: Apple's adult-content filter plus every name
    /// above. No exceptions, ever.
    static func policy(typedDomains: [String]) -> WebContentSettings.FilterPolicy {
        .auto(Set(domains(adding: typedDomains).map { WebDomain(domain: $0) }), except: [])
    }

    /// The policy a block session or a schedule writes to its own store: its
    /// own names only, exactly as before the guard existed.
    ///
    /// The guard's adult filter lives in the guard's store, and iOS applies the
    /// most restrictive combination of stores (WWDC22). An earlier version also
    /// made sessions write `.auto` while the guard was on, as belt and braces;
    /// with the guard, a session and a schedule each holding `.auto` on an
    /// iOS 26.5 iPhone, nothing was blocked at all, YouTube included
    /// (DEV-1, 2026-11-06). Stacking `.auto` across stores is undocumented, so
    /// a session never writes it.
    static func sessionPolicy(domains: [String]) -> WebContentSettings.FilterPolicy? {
        guard !domains.isEmpty else { return nil }
        return .specific(Set(domains.map { WebDomain(domain: $0) }))
    }
}
