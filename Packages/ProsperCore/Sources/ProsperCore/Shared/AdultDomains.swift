import Foundation

/// The adult sites both guards block by name (E9). On the iPhone these sit on
/// top of Apple's adult-content classifier, inside a 50-name filter budget, so
/// the list is short (see `AdultDomainList`). The Mac has no such budget and
/// blocks `AdultDomains.mac` as well (PLAN.md M2.1).
///
/// Lower-case bare domains, exactly as `BlockDomain.normalize` produces them;
/// subdomains are covered by suffix matching.
public enum AdultDomains {
    public static let builtIn: [String] = [
        // Tube sites
        "pornhub.com",
        "xvideos.com",
        "xnxx.com",
        "xhamster.com",
        "spankbang.com",
        "motherless.com",
        // Cam sites and creator platforms: clean landing pages, so classifiers miss them
        "chaturbate.com",
        "stripchat.com",
        "onlyfans.com",
        // Clip host and drawn content
        "redgifs.com",
        "nhentai.net",
        // The directory used to find every other site
        "theporndude.com",
    ]
}
