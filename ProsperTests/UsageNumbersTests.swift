import Testing
import Foundation
@testable import Prosper

private func minutes(_ m: Double) -> TimeInterval { m * 60 }

/// The Today hero and the product list add up app time and website time that
/// iOS reports separately — and website time is already inside the browser's.
/// A mistake here shows the user more waste (or more productive time) than they
/// had, with nothing on screen to give it away (QA-9).
struct TodayBalanceTests {
    typealias Usage = TodaySnapshot.ClassifiedUsage

    /// Catalog defaults only — no user labels.
    let classification = SharedClassification.Snapshot()

    private func site(_ host: String, _ m: Double) -> Usage {
        Usage(id: host, name: host, duration: minutes(m), timeClass: classification.timeClass(domain: host))
    }

    @Test("A classified site is carved out of the labelled browser: 40 / 20 / 60, not 60 / 20 / 40")
    func browserAndSiteBothLabelled() {
        let snapshot = TodaySnapshot.assemble(
            total: minutes(120),
            pickups: 0,
            notifications: 0,
            apps: [
                Usage(id: "com.google.chrome.ios", name: "Chrome", duration: minutes(60), timeClass: .productive),
                Usage(id: "com.example.other", name: "Other", duration: minutes(60), timeClass: nil),
            ],
            sites: [site("instagram.com", 20)],
            userHasLabels: true
        )
        #expect(snapshot.balance.productive == minutes(40))
        #expect(snapshot.balance.distracting == minutes(20))
        #expect(snapshot.balance.rest == 0)
        #expect(snapshot.balance.unclassified == minutes(60))
        #expect(snapshot.balance.total == minutes(120))
    }

    @Test("The waste rows add up to exactly the Wasted headline")
    func rowsMatchHeadline() {
        let snapshot = TodaySnapshot.assemble(
            total: minutes(120),
            pickups: 0,
            notifications: 0,
            apps: [Usage(id: "com.google.chrome.ios", name: "Chrome", duration: minutes(60), timeClass: .productive)],
            sites: [site("instagram.com", 20)],
            userHasLabels: true
        )
        #expect(snapshot.allWaste.map(\.name) == ["Instagram"])
        #expect(snapshot.allWaste.reduce(0) { $0 + $1.duration } == snapshot.balance.distracting)
        #expect(snapshot.topWaste.first?.duration == minutes(20))
    }

    @Test("A distracting browser keeps only the browsing not already filed under a site")
    func distractingBrowserIsNotCountedTwice() {
        let snapshot = TodaySnapshot.assemble(
            total: minutes(60),
            pickups: 0,
            notifications: 0,
            apps: [Usage(id: "com.apple.mobilesafari", name: "Safari", duration: minutes(60), timeClass: .distracting)],
            sites: [site("instagram.com", 20), site("unlabelled.example", 15)],
            userHasLabels: true
        )
        // 20m Instagram + the remaining 40m of Safari; the unlabelled site's
        // 15m stays inside Safari's 40m rather than being added again.
        #expect(snapshot.balance.distracting == minutes(60))
        #expect(snapshot.balance.unclassified == 0)
        let rows = Dictionary(uniqueKeysWithValues: snapshot.allWaste.map { ($0.name, $0.duration) })
        #expect(rows["Instagram"] == minutes(20))
        #expect(rows["Safari"] == minutes(40))
        #expect(snapshot.allWaste.reduce(0) { $0 + $1.duration } == snapshot.balance.distracting)
    }

    @Test("When labelled time still overruns the total, rows shrink with the headline")
    func safetyNetScalesRowsToo() {
        // Site time with no browser to take it from: 30 + 30 labelled in 40 tracked.
        let snapshot = TodaySnapshot.assemble(
            total: minutes(40),
            pickups: 0,
            notifications: 0,
            apps: [Usage(id: "tiktok", name: "TikTok", duration: minutes(30), timeClass: .distracting)],
            sites: [site("instagram.com", 30)],
            userHasLabels: false
        )
        #expect(snapshot.balance.total == minutes(40))
        #expect(snapshot.balance.distracting == minutes(40))
        let rowSum = snapshot.allWaste.reduce(0) { $0 + $1.duration }
        #expect(abs(rowSum - snapshot.balance.distracting) < 0.001)
    }

    @Test("Unlabelled time is never assumed productive")
    func nothingLabelledIsAllUnclassified() {
        let snapshot = TodaySnapshot.assemble(
            total: minutes(50),
            pickups: 3,
            notifications: 2,
            apps: [Usage(id: "notes", name: "Notes", duration: minutes(50), timeClass: nil)],
            sites: [],
            userHasLabels: false
        )
        #expect(snapshot.balance.unclassified == minutes(50))
        #expect(snapshot.balance.productive == 0)
        #expect(!snapshot.hasClassification)
        #expect(snapshot.totalPickups == 3)
        #expect(snapshot.totalNotifications == 2)
    }
}

struct RankedProductsTests {
    @Test("Browser rows lose the website time already listed under its own rows")
    func browserSubtraction() {
        let products = UsageSummary.rankedProducts(
            apps: [
                UsageItem(id: "safari", name: "Safari", duration: minutes(60), pickups: 4),
                UsageItem(id: "notes", name: "Notes", duration: minutes(30), pickups: 1),
            ],
            sites: [
                UsageItem(id: "youtube.com", name: "youtube.com", duration: minutes(20), pickups: 0),
                UsageItem(id: "foo.example", name: "foo.example", duration: minutes(10), pickups: 0),
            ]
        )
        let rows = Dictionary(uniqueKeysWithValues: products.map { ($0.name, $0.duration) })
        #expect(rows["Safari"] == minutes(30))
        #expect(rows["YouTube"] == minutes(20))
        #expect(rows["foo.example"] == minutes(10))
        #expect(rows["Notes"] == minutes(30))
        // The list adds up to the app time — nothing counted twice.
        #expect(products.reduce(0) { $0 + $1.duration } == minutes(90))
    }

    @Test("With no browser, nothing is scaled")
    func zeroBrowserScale() {
        let products = UsageSummary.rankedProducts(
            apps: [
                UsageItem(id: "notes", name: "Notes", duration: minutes(30), pickups: 1),
                UsageItem(id: "ledger", name: "Ledger Live", duration: minutes(15), pickups: 1),
            ],
            sites: [UsageItem(id: "foo.example", name: "foo.example", duration: minutes(10), pickups: 0)]
        )
        let rows = Dictionary(uniqueKeysWithValues: products.map { ($0.name, $0.duration) })
        #expect(rows["Notes"] == minutes(30))
        #expect(rows["Ledger Live"] == minutes(15))
        #expect(rows["foo.example"] == minutes(10))
    }

    @Test("A browser never goes negative when sites outrun it")
    func browserFloorsAtZero() {
        let products = UsageSummary.rankedProducts(
            apps: [UsageItem(id: "safari", name: "Safari", duration: minutes(10), pickups: 0)],
            sites: [UsageItem(id: "foo.example", name: "foo.example", duration: minutes(25), pickups: 0)]
        )
        #expect(!products.contains { $0.name == "Safari" })
        #expect(products.allSatisfy { $0.duration >= 0 })
    }
}
