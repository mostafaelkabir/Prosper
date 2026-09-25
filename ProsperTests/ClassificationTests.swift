import Testing
import Foundation
@testable import Prosper

/// Which class a site or app lands in decides every number on Today. A wrong
/// answer files waste as productive, or the user's own label as the catalog's
/// guess, with nothing on screen to show it happened (QA-9).
struct TimeClassTests {
    typealias Snapshot = SharedClassification.Snapshot

    @Test("An item tagged in several classes resolves distracting > rest > productive")
    func priority() {
        let all = Snapshot(productiveDomains: ["example.com"], distractingDomains: ["example.com"], restDomains: ["example.com"])
        #expect(all.timeClass(domain: "example.com") == .distracting)

        let restAndProductive = Snapshot(productiveDomains: ["example.com"], restDomains: ["example.com"])
        #expect(restAndProductive.timeClass(domain: "example.com") == .rest)

        let productiveOnly = Snapshot(productiveDomains: ["example.com"])
        #expect(productiveOnly.timeClass(domain: "example.com") == .productive)
    }

    @Test("www. is ignored on either side")
    func wwwStripping() {
        #expect(Snapshot(restDomains: ["example.com"]).timeClass(domain: "www.example.com") == .rest)
        #expect(Snapshot(restDomains: ["www.example.com"]).timeClass(domain: "example.com") == .rest)
        #expect(Snapshot(restDomains: ["Example.COM"]).timeClass(domain: "WWW.example.com") == .rest)
    }

    @Test("A tagged domain covers its subdomains, but not look-alike hosts")
    func subdomainMatch() {
        let snapshot = Snapshot(productiveDomains: ["example.com"])
        #expect(snapshot.timeClass(domain: "m.example.com") == .productive)
        #expect(snapshot.timeClass(domain: "docs.eu.example.com") == .productive)
        #expect(snapshot.timeClass(domain: "notexample.com") == nil)
        #expect(snapshot.timeClass(domain: "example.com.evil.net") == nil)
    }

    @Test("The user's label beats the catalog's default")
    func userLabelBeatsCatalogDefault() {
        // Instagram ships defaulting to distracting.
        #expect(Snapshot().timeClass(domain: "instagram.com") == .distracting)
        #expect(Snapshot().timeClass(appToken: nil, categoryToken: nil, appName: "Instagram") == .distracting)

        let relabelled = Snapshot(productiveDomains: ["instagram.com"])
        #expect(relabelled.timeClass(domain: "instagram.com") == .productive)
        #expect(relabelled.timeClass(domain: "scontent.cdninstagram.com") == .productive)
        #expect(relabelled.timeClass(appToken: nil, categoryToken: nil, appName: "Instagram") == .productive)
    }

    @Test("Nothing known means no class — never a guess")
    func nilAndEmptyAreUnclassified() {
        let snapshot = Snapshot(productiveDomains: ["example.com"])
        #expect(snapshot.timeClass(domain: nil) == nil)
        #expect(snapshot.timeClass(domain: "") == nil)
        #expect(snapshot.timeClass(appToken: nil, categoryToken: nil, appName: nil) == nil)
        #expect(snapshot.timeClass(appToken: nil, categoryToken: nil, appName: "") == nil)
        #expect(snapshot.timeClass(appToken: nil, categoryToken: nil, appName: "Notes") == nil)
        #expect(Snapshot().isEmpty)
    }
}

struct PlatformCatalogTests {
    @Test("Browsers are matched on whole words", arguments: [
        "Safari", "Chrome", "Firefox", "Microsoft Edge", "Opera", "Opera GX",
        "Arc", "Arc Search", "DuckDuckGo", "Brave", "Firefox Focus",
    ])
    func browsers(name: String) {
        #expect(PlatformCatalog.isBrowser(name))
    }

    @Test("Words that merely contain a browser name are not browsers", arguments: [
        "Ledger Live", "Knowledge", "Operator", "Archive", "Search", "Notes",
    ])
    func notBrowsers(name: String) {
        #expect(!PlatformCatalog.isBrowser(name))
    }

    @Test("No name, no browser")
    func nilIsNotBrowser() {
        #expect(!PlatformCatalog.isBrowser(nil))
        #expect(!PlatformCatalog.isBrowser(""))
    }

    @Test("A dotted keyword matches whole DNS labels only: reddit.com is not X via t.co")
    func dottedKeywordsMatchLabels() throws {
        let x = try #require(PlatformCatalog.platform(id: "x"))
        #expect(!x.matches("reddit.com"))
        #expect(!x.matches("microsoft.com"))
        #expect(x.matches("t.co"))
        #expect(x.matches("mobile.x.com"))
        #expect(PlatformCatalog.match("reddit.com")?.id == "reddit")
    }

    @Test("CDN hosts cluster under their platform")
    func cdnHostsCluster() {
        #expect(PlatformCatalog.match("r1---sn-x.googlevideo.com")?.id == "youtube")
        #expect(PlatformCatalog.match("scontent.cdninstagram.com")?.id == "instagram")
        #expect(PlatformCatalog.match("YouTube Music")?.id == "youtube")
        #expect(PlatformCatalog.match(nil) == nil)
        #expect(PlatformCatalog.match("") == nil)
    }
}
