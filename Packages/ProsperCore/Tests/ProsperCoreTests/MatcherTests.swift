import Foundation
import Testing
@testable import ProsperCore

struct MatcherTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Suffix matching is on whole labels")
    func suffix() {
        let m = DomainMatcher(["youtube.com", "x.com"])
        #expect(m.matchedDomain("m.youtube.com") == "youtube.com")
        #expect(m.matchedDomain("YOUTUBE.COM.") == "youtube.com")
        #expect(m.matchedDomain("notyoutube.com") == nil)
        #expect(m.matchedDomain("x.com.evil.net") == nil)
        #expect(m.matchedDomain("api.x.com") == "x.com")
    }

    @Test("Adult names are caught without catching ordinary places")
    func guardWords() {
        for host in ["freeporn.example", "xxxvideos.net", "nudes-archive.net", "cdn.hentaistream.org", "example.xxx", "hot.sex", "milfsite.com"] {
            #expect(GuardMatcher.looksAdult(host), "\(host) should be caught")
        }
        for host in ["essex.ac.uk", "sussex.com", "sextant.io", "middlesex.edu", "github.com", "nudge.com", "milford.edu", "apple.com", "google.com"] {
            #expect(!GuardMatcher.looksAdult(host), "\(host) should pass")
        }
    }

    @Test("Active rules say why a host or app is blocked")
    func activeRules() throws {
        let (rules, _) = try RulesBook.startingSession(.empty, minutes: 30, domains: ["reddit.com"], bundleIDs: ["com.app"], platformIDs: ["youtube"], now: now)
        let active = ActiveRules(rules: rules, at: now)
        #expect(active.reason(forHost: "old.reddit.com") == .session(endsAt: now.addingTimeInterval(1800)))
        #expect(active.reason(forHost: "www.youtube.com") != nil)
        #expect(active.reason(forHost: "pornhub.com") == nil) // guard off
        #expect(active.reason(forBundleID: "com.app") != nil)
        #expect(active.validUntil <= now.addingTimeInterval(60))

        let later = ActiveRules(rules: rules, at: now.addingTimeInterval(1800))
        #expect(later.reason(forHost: "reddit.com") == nil)
    }

    @Test("The guard blocks its list, its keywords and its apps, with no end")
    func guardRules() {
        var rules = RulesBook.enablingGuard(.empty, now: now)
        rules = RulesBook.addingToGuard(rules, domains: ["mysite.org"], bundleIDs: ["com.bad"])
        let active = ActiveRules(rules: rules, at: now)
        #expect(active.reason(forHost: "www.pornhub.com") == .adultGuard)
        #expect(active.reason(forHost: "mysite.org") == .adultGuard)
        #expect(active.reason(forHost: "anything-porn.net") == .adultGuard)
        #expect(active.reason(forHost: "apple.com") == nil)
        #expect(active.reason(forBundleID: "com.bad") == .adultGuard)
        #expect(active.safeSearch && active.closeBypasses)
    }

    @Test("Bypass ports: QUIC, DNS over TLS, DoH by address")
    func bypass() {
        #expect(BypassRules.verdict(isUDP: true, remotePort: 443, remoteAddress: "1.2.3.4") == .block)
        #expect(BypassRules.verdict(isUDP: false, remotePort: 853, remoteAddress: "1.2.3.4") == .block)
        #expect(BypassRules.verdict(isUDP: false, remotePort: 443, remoteAddress: "1.1.1.1") == .block)
        #expect(BypassRules.verdict(isUDP: false, remotePort: 443, remoteAddress: "17.253.144.10") == .allow)
        #expect(BypassRules.isBypassHost("mozilla.cloudflare-dns.com"))
        #expect(BypassRules.isBypassHost("mask.icloud.com"))
        #expect(!BypassRules.isBypassHost("icloud.com"))
    }

    @Test("Schedule windows run past midnight and respect weekdays")
    func window() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let night = ScheduleWindow(startMinute: 22 * 60, endMinute: 7 * 60, weekdays: [6]) // Friday
        let friday2330 = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 23, minute: 30))!
        let saturday0630 = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 6, minute: 30))!
        let saturday2330 = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 23, minute: 30))!
        #expect(night.contains(friday2330, calendar: cal))
        #expect(night.contains(saturday0630, calendar: cal))
        #expect(!night.contains(saturday2330, calendar: cal))
        #expect(night.spanMinutes == 9 * 60)
    }

    @Test("Shared BlockDomain normalisation (moved from the iOS app)")
    func blockDomain() {
        #expect(BlockDomain.normalize("https://www.Reddit.com/r/all") == "reddit.com")
        #expect(BlockDomain.normalize("bücher.de") == "xn--bcher-kva.de")
        #expect(BlockDomain.normalize("localhost") == nil)
    }

    @Test("Every Mac adult domain is already normalised")
    func adultListNormalised() {
        for domain in AdultDomains.mac {
            #expect(BlockDomain.normalize(domain) == domain, "\(domain)")
        }
        #expect(AdultDomains.mac.isSuperset(of: AdultDomains.builtIn))
    }
}
