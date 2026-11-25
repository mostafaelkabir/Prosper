import Testing
import Foundation
import FamilyControls
import UIKit
@testable import Prosper

/// The day ledger files every app and site under its label (UX-29). It sits
/// one tap behind the Today ring, so its totals have to be the ring's, and
/// its rows must never count the same minutes twice.
struct DayLedgerTests {
    typealias Usage = TodaySnapshot.ClassifiedUsage

    private func minutes(_ m: Double) -> TimeInterval { m * 60 }

    private func day(total: Double, apps: [Usage], sites: [Usage] = []) -> ClassifiedDay {
        var day = ClassifiedDay()
        day.total = minutes(total)
        day.apps = apps
        day.sites = sites
        day.userHasLabels = true
        return day
    }

    /// Scaled durations pick up floating-point dust; a second is far below
    /// anything the screen shows.
    private func close(_ a: TimeInterval?, _ b: TimeInterval) -> Bool {
        guard let a else { return false }
        return abs(a - b) < 1
    }

    private func group(_ ledger: DayLedger, _ timeClass: TimeClass) -> DayLedger.Group? {
        ledger.groups.first { $0.timeClass == timeClass }
    }

    @Test("Groups read: not labelled, distracting, productive, rest. Empty ones are left out")
    func orderAndOmission() {
        let ledger = DayLedger.assemble(day(total: 60, apps: [
            Usage(id: "notes", name: "Notes", duration: minutes(10), timeClass: .productive),
            Usage(id: "game", name: "Game", duration: minutes(30), timeClass: .distracting),
            Usage(id: "maps", name: "Maps", duration: minutes(20), timeClass: nil),
        ]))
        #expect(ledger.groups.map(\.timeClass) == [.unclassified, .distracting, .productive])
        #expect(group(ledger, .rest) == nil)
    }

    @Test("Every group's total is the Today ring's number for that label")
    func totalsMatchTheRing() {
        let apps = [
            Usage(id: "safari", name: "Safari", duration: minutes(60), timeClass: .productive),
            Usage(id: "game", name: "Game", duration: minutes(25), timeClass: .distracting),
            Usage(id: "maps", name: "Maps", duration: minutes(15), timeClass: nil),
        ]
        let sites = [Usage(id: "instagram.com", name: "instagram.com", duration: minutes(20), timeClass: .distracting)]
        let ledger = DayLedger.assemble(day(total: 100, apps: apps, sites: sites))
        let ring = TodaySnapshot.assemble(total: minutes(100), pickups: 0, notifications: 0, apps: apps, sites: sites, userHasLabels: true).balance

        #expect(ledger.balance == ring)
        for timeClass in TimeClass.allCases {
            #expect(close(group(ledger, timeClass)?.total ?? 0, ring.value(timeClass)))
        }
        // Safari gave up the 20 minutes that were Instagram.
        #expect(close(group(ledger, .productive)?.rows.first?.duration, minutes(40)))
        #expect(close(group(ledger, .distracting)?.total, minutes(45)))
    }

    @Test("A site with no label gets its own row when the browser has none either, and is not counted twice")
    func unlabelledSiteIsListedOnce() {
        let ledger = DayLedger.assemble(day(
            total: 30,
            apps: [Usage(id: "safari", name: "Safari", duration: minutes(30), timeClass: nil)],
            sites: [Usage(id: "news.example", name: "news.example", duration: minutes(12), timeClass: nil)]
        ))
        let rows = group(ledger, .unclassified)?.rows ?? []
        #expect(rows.map(\.name) == ["Safari", "news.example"])
        #expect(close(rows.first?.duration, minutes(18)))
        #expect(close(rows.last?.duration, minutes(12)))
        #expect(close(group(ledger, .unclassified)?.total, minutes(30)))
    }

    @Test("Unlabelled browsing stays inside a labelled browser, as it does in the ring")
    func unlabelledSiteInsideLabelledBrowser() {
        let ledger = DayLedger.assemble(day(
            total: 30,
            apps: [Usage(id: "safari", name: "Safari", duration: minutes(30), timeClass: .productive)],
            sites: [Usage(id: "news.example", name: "news.example", duration: minutes(12), timeClass: nil)]
        ))
        #expect(group(ledger, .productive)?.rows.count == 1)
        #expect(close(group(ledger, .productive)?.rows.first?.duration, minutes(30)))
        #expect(group(ledger, .unclassified) == nil)
    }

    @Test("A platform's app and sites are one row under one label")
    func platformIsOneRow() {
        let ledger = DayLedger.assemble(day(
            total: 60,
            apps: [
                Usage(id: "com.google.ios.youtube", name: "YouTube", duration: minutes(30), timeClass: .distracting),
                Usage(id: "safari", name: "Safari", duration: minutes(30), timeClass: nil),
            ],
            sites: [
                Usage(id: "youtube.com", name: "youtube.com", duration: minutes(10), timeClass: .distracting),
                Usage(id: "r1.googlevideo.com", name: "r1.googlevideo.com", duration: minutes(5), timeClass: .distracting),
            ]
        ))
        let distracting = group(ledger, .distracting)
        #expect(distracting?.rows.count == 1)
        #expect(distracting?.rows.first?.name == "YouTube")
        #expect(close(distracting?.rows.first?.duration, minutes(45)))
        #expect(close(group(ledger, .unclassified)?.rows.first?.duration, minutes(15)))
    }

    @Test("Rows never add up to more than their group, even when Screen Time's numbers overlap")
    func rowsNeverExceedTheGroup() {
        // 40 minutes of labelled site time with no browser to take it from,
        // on a day iOS says was 30 minutes long.
        let ledger = DayLedger.assemble(day(
            total: 30,
            apps: [Usage(id: "game", name: "Game", duration: minutes(20), timeClass: .distracting)],
            sites: [Usage(id: "docs.example", name: "docs.example", duration: minutes(40), timeClass: .productive)]
        ))
        for group in ledger.groups {
            let listed = group.rows.reduce(0) { $0 + $1.duration }
            #expect(listed <= group.total + 0.5)
        }
        #expect(abs(ledger.balance.total - minutes(30)) < 0.5)
    }

    @Test("A long group shows its biggest rows and says what it left out")
    func longGroupsAreCapped() {
        let apps = (0..<(DayLedger.maxRows + 5)).map { index in
            Usage(id: "app\(index)", name: "App \(index)", duration: minutes(Double(index + 1)), timeClass: nil)
        }
        let total = apps.reduce(0) { $0 + $1.duration } / 60
        let unlabelled = group(DayLedger.assemble(day(total: total, apps: apps)), .unclassified)
        #expect(unlabelled?.rows.count == DayLedger.maxRows)
        #expect(unlabelled?.hiddenCount == 5)
        #expect(close(unlabelled?.hiddenDuration, minutes(1 + 2 + 3 + 4 + 5)))
        #expect(unlabelled?.rows.first?.name == "App \(DayLedger.maxRows + 4)")
    }

    @Test("An empty day is empty")
    func emptyDay() {
        let ledger = DayLedger.assemble(ClassifiedDay())
        #expect(ledger.isEmpty)
        #expect(ledger.groups.isEmpty)
    }
}

/// The pieces of the block list a person builds on the Lock tab (UX-28).
struct BlockListTests {
    @Test("A platform is one chip, whatever number of addresses it has on the list")
    func onePerPlatform() {
        let chips = SiteList.onePerPlatform(["youtube.com", "news.example", "youtu.be", "m.youtube.com", "reddit.com", "redd.it"])
        #expect(chips == ["youtube.com", "news.example", "reddit.com"])
    }

    @Test("An unknown site always gets the same colour and its own initial")
    func siteTintIsStable() {
        #expect(SiteTint.index(for: "news.example") == SiteTint.index(for: "NEWS.example"))
        #expect(SiteTint.palette.indices.contains(SiteTint.index(for: "a.b")))
        #expect(SiteTint.initial(for: "news.example") == "N")
        #expect(SiteTint.initial(for: "9gag.com") == "9")
        #expect(SiteTint.initial(for: "") == "?")
    }

    @Test("Every unknown-site colour keeps its white initial readable (4.5:1)")
    func siteTintContrast() {
        func channel(_ value: UInt) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        for hex in SiteTint.palette {
            let luminance = 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
            #expect(1.05 / (luminance + 0.05) >= 4.5, "0x\(String(hex, radix: 16)) is too light")
        }
    }

    @Test("Every bundled brand mark belongs to a catalog platform and loads from the app")
    func brandLogosAreBundled() {
        for id in BrandLogo.platforms {
            #expect(PlatformCatalog.platform(id: id) != nil, "\(id) is not in the catalog")
            #expect(UIImage(named: BrandLogo.imageName(id), in: Bundle(for: UserSettings.self), with: nil) != nil, "\(id) has no image")
        }
    }

    @Test("Label sets: an empty selection takes nothing away and counts as empty")
    func labelSets() {
        let empty = FamilyActivitySelection()
        #expect(LabelSets.isEmpty(empty))
        #expect(LabelSets.removing(empty, from: empty) == empty)
        #expect(LabelSets.added(in: empty, since: empty) == empty)
    }
}
