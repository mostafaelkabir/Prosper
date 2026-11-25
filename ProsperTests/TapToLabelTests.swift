import Testing
import Foundation
@testable import Prosper

/// Tap to label: a usage row links into the app, and one tap files the thing
/// under one label. A link the app cannot read is a dead tap; a label that
/// lands in two lists counts the same time twice.
struct TapToLabelTests {

    // MARK: The link

    @Test func platformLinkRoundTrips() throws {
        let url = try #require(LabelTarget.platform("youtube").url)
        #expect(url.absoluteString == "stolenglance://label?platform=youtube")
        #expect(LabelTarget(url: url) == .platform("youtube"))
    }

    @Test func siteLinkRoundTrips() throws {
        let url = try #require(LabelTarget.site("news.com").url)
        #expect(LabelTarget(url: url) == .site("news.com"))
    }

    @Test func linksFromElsewhereAreIgnored() {
        #expect(LabelTarget(url: URL(string: "https://label?platform=youtube")!) == nil)
        #expect(LabelTarget(url: URL(string: "stolenglance://lock?platform=youtube")!) == nil)
        #expect(LabelTarget(url: URL(string: "stolenglance://label?platform=nope")!) == nil)
        #expect(LabelTarget(url: URL(string: "stolenglance://label?app=notatoken")!) == nil)
    }

    // MARK: Which thing a row labels

    @Test func platformRowLabelsThePlatform() {
        let row = UsageItem(id: "youtube", name: "YouTube", duration: 60, pickups: 0, platformID: "youtube")
        #expect(LabelTarget(item: row) == .platform("youtube"))
    }

    @Test func appNamedLikeAPlatformLabelsThePlatform() {
        let row = UsageItem(id: "x", name: "Instagram", duration: 60, pickups: 0)
        #expect(LabelTarget(item: row) == .platform("instagram"))
    }

    @Test func websiteRowLabelsTheSite() {
        let row = UsageItem(id: "news.com", name: "news.com", duration: 60, pickups: 0)
        #expect(LabelTarget(item: row) == .site("news.com"))
    }

    @Test func unnamedAppWithoutTokenHasNoPill() {
        let row = UsageItem(id: "mail", name: "Mail", duration: 60, pickups: 0)
        #expect(LabelTarget(item: row) == nil)
    }

    // MARK: One label at a time

    @Test func relabellingASiteMovesIt() {
        var book = LabelBook()
        book.assign(.distracting, to: .site("news.com"))
        book.assign(.productive, to: .site("news.com"))
        #expect(book.productiveDomains == ["news.com"])
        #expect(book.distractingDomains.isEmpty)
        #expect(book.current(.site("news.com")) == .productive)
    }

    @Test func platformMovesAllItsDomainsTogether() throws {
        let youtube = try #require(PlatformCatalog.platform(id: "youtube"))
        var book = LabelBook()
        book.assign(.rest, to: .platform("youtube"))
        #expect(Set(book.restDomains) == Set(youtube.domains))
        book.assign(.productive, to: .platform("youtube"))
        #expect(book.restDomains.isEmpty)
        #expect(Set(book.productiveDomains) == Set(youtube.domains))
        #expect(book.current(.platform("youtube")) == .productive)
    }

    @Test func removingAPlatformLabelFallsBackToItsUsualOne() {
        var book = LabelBook()
        book.assign(.productive, to: .platform("youtube"))
        #expect(book.hasOwnLabel(.platform("youtube")))
        book.assign(nil, to: .platform("youtube"))
        #expect(!book.hasOwnLabel(.platform("youtube")))
        // YouTube is Distracting out of the box (UX-20).
        #expect(book.current(.platform("youtube")) == .distracting)
    }

    @Test func removingASiteLabelLeavesItUnlabelled() {
        var book = LabelBook()
        book.assign(.rest, to: .site("news.com"))
        book.assign(nil, to: .site("news.com"))
        #expect(book.current(.site("news.com")) == .unclassified)
        #expect(book.restDomains.isEmpty)
    }
}
