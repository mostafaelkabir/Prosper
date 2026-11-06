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
/// The list is deliberately short of the filter's 50-domain capacity so the
/// user can add a site that slipped through, for good, without a new build.
enum AdultDomainList {
    /// Apple's web content filter accepts at most this many named domains at
    /// once (same limit as `BlockingService.maxDomains`).
    static let filterCapacity = 50

    /// Blocked by name. Lower-case bare domains, exactly as `BlockDomain.normalize`
    /// would produce them; the unit tests hold that line. Subdomains are
    /// covered by the filter's domain matching.
    static let builtIn: [String] = [
        // Tube sites
        "pornhub.com",
        "xvideos.com",
        "xnxx.com",
        "xhamster.com",
        "redtube.com",
        "youporn.com",
        "spankbang.com",
        "eporner.com",
        "tube8.com",
        "porntrex.com",
        "hqporner.com",
        "beeg.com",
        "motherless.com",
        "thisvid.com",
        "porn.com",
        "sex.com",
        // Cam sites
        "chaturbate.com",
        "stripchat.com",
        "livejasmin.com",
        "bongacams.com",
        "cam4.com",
        "myfreecams.com",
        "camsoda.com",
        // Creator platforms: clean landing pages, so generic filters miss them
        "onlyfans.com",
        "fansly.com",
        // Hentai / drawn
        "nhentai.net",
        "e-hentai.org",
        "hanime.tv",
        "rule34.xxx",
        // Image and clip hosts
        "redgifs.com",
        "imagefap.com",
        "erome.com",
        "fapello.com",
        // Directories and search engines: the way around every other block
        "theporndude.com",
        "pornmd.com",
        // Leak archives: new enough that classifiers lag
        "coomer.su",
        "kemono.su",
        "simpcity.su",
        // Studios
        "brazzers.com",
        "bangbros.com",
    ]

    /// How many sites the user can still add by name.
    static var userSlots: Int { filterCapacity - builtIn.count }

    /// The built-in list plus the user's additions: deduplicated, in order,
    /// and never longer than the filter will accept.
    static func domains(adding typed: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for domain in builtIn + typed where seen.insert(domain).inserted {
            result.append(domain)
        }
        return Array(result.prefix(filterCapacity))
    }

    /// The guard's own policy: Apple's adult-content filter plus every name
    /// above. No exceptions, ever.
    static func policy(typedDomains: [String]) -> WebContentSettings.FilterPolicy {
        .auto(Set(domains(adding: typedDomains).map { WebDomain(domain: $0) }), except: [])
    }

    /// The policy a *block session* writes to its own store.
    ///
    /// The guard lives in a separate `ManagedSettingsStore`, so a session
    /// starting or ending never touches it. But iOS merges the web filter
    /// across stores by rules Apple does not document in detail, and the one
    /// outcome that must be impossible is a session's `.specific` list
    /// replacing the adult filter for the length of the session. So while the
    /// guard is on, a session carries the adult filter as well: whichever store
    /// iOS listens to, the filter stays up.
    static func sessionPolicy(domains: [String], guardOn: Bool) -> WebContentSettings.FilterPolicy? {
        guard !domains.isEmpty else { return nil }
        let set = Set(domains.map { WebDomain(domain: $0) })
        return guardOn ? .auto(set, except: []) : .specific(set)
    }
}
