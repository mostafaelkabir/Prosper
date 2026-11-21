import Foundation
import Testing
@testable import ProsperCore

/// M3.7: attention insights from the ordered timeline.
struct AttentionTests {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2027-01-15 09:00 UTC.
    static let nine = Date(timeIntervalSince1970: 1_800_003_600)

    static let xcode = "com.apple.dt.Xcode"
    static let chrome = "com.google.Chrome"
    static let slack = "com.tinyspeck.slackmacgap"
    static let terminal = "com.apple.Terminal"
    /// Classed as rest: an interruption to work, not work.
    static let messages = "com.apple.MobileSMS"

    /// Builds a day from (app, site, seconds, gap-before) steps starting at 9 AM.
    static func day(_ steps: [(String, String?, Double, Double)], start: Date = nine) -> UsageDay {
        var day = UsageDay(day: UsageDay.key(for: start, calendar: utc))
        day.apps[xcode] = AppUsage(name: "Xcode", category: "public.app-category.developer-tools")
        day.apps[chrome] = AppUsage(name: "Google Chrome", isBrowser: true)
        day.apps[slack] = AppUsage(name: "Slack")
        day.apps[terminal] = AppUsage(name: "Terminal")
        day.apps[messages] = AppUsage(name: "Messages")
        var t = start
        for (app, site, seconds, gap) in steps {
            t = t.addingTimeInterval(gap)
            day.timeline.append(Stint(start: t, seconds: seconds, app: app, site: site))
            t = t.addingTimeInterval(seconds)
        }
        return day
    }

    static func report(_ days: [UsageDay]) -> AttentionReport {
        Attention.report(days: days, classifier: MacClassifier(), calendar: utc)
    }

    // MARK: Recording

    @Test("The sampler's 30-second re-bookings extend one stint instead of making new ones")
    func rebookingExtends() {
        var day = UsageDay(day: "2027-01-15")
        let app = AppUsage(name: "Xcode")
        let t = Self.nine
        day.record(bundleID: Self.xcode, app: app, site: nil, from: t, to: t + 30, timeClass: .productive, calendar: Self.utc)
        day.record(bundleID: Self.xcode, app: app, site: nil, from: t + 30, to: t + 60, timeClass: .productive, calendar: Self.utc)
        day.record(bundleID: Self.chrome, app: AppUsage(name: "Chrome", isBrowser: true), site: "github.com", from: t + 60, to: t + 90, timeClass: nil, calendar: Self.utc)
        // Back to Xcode after a minute away: a new stint, not an extension.
        day.record(bundleID: Self.xcode, app: app, site: nil, from: t + 150, to: t + 200, timeClass: .productive, calendar: Self.utc)
        #expect(day.timeline.count == 3)
        #expect(day.timeline[0].seconds == 60)
        #expect(day.timeline[1].site == "github.com")
        #expect(day.timeline[2].start == t + 150)
    }

    @Test("A usage file from before the timeline still loads, with an empty timeline")
    func oldFileDecodes() throws {
        let old = #"{"apps":{},"day":"2026-10-01","hourly":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"hourlyDistracting":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],"longestDistractingRun":0,"sites":{},"unlocks":3}"#
        let day = try MacStore.decoder.decode(UsageDay.self, from: Data(old.utf8))
        #expect(day.unlocks == 3)
        #expect(day.timeline.isEmpty)
        #expect(Self.report([day]).isEmpty)
    }

    @Test("Stints round-trip through the store's JSON in their short form")
    func stintRoundTrip() throws {
        var day = Self.day([(Self.chrome, "youtube.com", 12.345, 0)])
        day.timeline.append(Stint(start: Self.nine + 100, seconds: 5, app: Self.xcode))
        let data = try MacStore.encoder.encode(day)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"a\" : \"com.google.Chrome\""))
        let back = try MacStore.decoder.decode(UsageDay.self, from: data)
        #expect(back.timeline.count == 2)
        #expect(abs(back.timeline[0].seconds - 12.35) < 0.001)
        #expect(back.timeline[0].site == "youtube.com")
        #expect(back.timeline[1].site == nil)
    }

    // MARK: Switching

    @Test("Switches count every change of app or site while present, not returns from a break")
    func switchesPerHour() throws {
        // 60 one-minute visits alternating Xcode and Slack: 59 switches in an hour.
        let steps = (0..<60).map { i in (i % 2 == 0 ? Self.xcode : Self.slack, String?.none, 60.0, 0.0) }
        // Then 10 minutes away and back to Slack: a new sitting, not a switch.
        let day = Self.day(steps + [(Self.slack, nil, 600, 600)])
        let r = Self.report([day])
        #expect(r.switches == 59)
        #expect(r.sittings == 2)
        #expect(r.activeSeconds == 4200)
        let perHour = try #require(r.switchesPerHour)
        #expect(abs(perHour - 59.0 / (4200.0 / 3600)) < 0.01)
        #expect(r.hourlySwitches[9] == 59)
    }

    @Test("A site change inside the browser is a switch; a passing empty tab is not")
    func browserSites() {
        let day = Self.day([
            (Self.xcode, nil, 600, 0),
            (Self.chrome, nil, 2, 0),            // new tab, typing an address
            (Self.chrome, "github.com", 300, 0),
            (Self.chrome, "youtube.com", 300, 0),
            (Self.chrome, "github.com", 300, 0),
        ])
        let r = Self.report([day])
        #expect(r.switches == 3)
        #expect(r.switchesIntoDistraction == 1)
    }

    @Test("The YouTube app and youtube.com are one thing, so moving between them is no switch")
    func platformsMerge() {
        var day = Self.day([(Self.chrome, "youtube.com", 300, 0), ("com.google.ios.youtube", nil, 300, 0)])
        day.apps["com.google.ios.youtube"] = AppUsage(name: "YouTube")
        let r = Self.report([day])
        #expect(r.switches == 0)
        #expect(r.longestDistractingVisit?.seconds == 600)
        #expect(r.longestDistractingVisit?.name == "YouTube")
    }

    @Test("Rates wait for half an hour of measurement")
    func ratesNeedTime() {
        let r = Self.report([Self.day([(Self.xcode, nil, 60, 0), (Self.slack, nil, 60, 0)])])
        #expect(r.switches == 1)
        #expect(r.switchesPerHour == nil)
        #expect(AttentionInsights.sentences(r).allSatisfy { $0.kind != .switching })
    }

    @Test("The most scattered hour is the one with the most switching per active hour")
    func scatteredHour() throws {
        // 9 AM: steady work. 10 AM: thirty-second hops between Slack and Chrome.
        let calm = [(Self.xcode, String?.none, 3600.0, 0.0)]
        let hops = (0..<120).map { i in (i % 2 == 0 ? Self.slack : Self.chrome, i % 2 == 0 ? String?.none : "news.ycombinator.com", 30.0, 0.0) }
        let r = Self.report([Self.day(calm + hops)])
        let peak = try #require(r.mostScatteredHour)
        #expect(peak.hour == 10)
        #expect(peak.perHour > 100)
        #expect(r.hourlyRate[9] != nil)
        #expect(r.hourlyRate[14] == nil)
    }

    // MARK: Holding and focus

    @Test("Median time on one thing comes from merged visits; a short pause does not split one")
    func medianVisit() {
        let day = Self.day([
            (Self.xcode, nil, 100, 0),
            (Self.xcode, nil, 100, 90),   // 90 s without input, same app: one visit
            (Self.slack, nil, 20, 0),
            (Self.terminal, nil, 40, 0),
        ])
        let r = Self.report([day])
        #expect(r.medianVisit == 40)   // visits: 200, 20, 40
        #expect(r.longestVisit?.name == "Xcode")
        #expect(r.longestVisit?.seconds == 200)
    }

    @Test("Short interruptions stay inside a focus block; a long one ends it")
    func focusBlocks() throws {
        let day = Self.day([
            (Self.xcode, nil, 15 * 60, 0),
            (Self.messages, nil, 45, 0),              // brief: inside the block
            (Self.xcode, nil, 15 * 60, 0),
            (Self.chrome, "youtube.com", 10 * 60, 0), // ends it
            (Self.xcode, nil, 10 * 60, 0),
        ])
        let r = Self.report([day])
        #expect(r.focusBlocks.count == 2)
        let first = r.focusBlocks[0]
        #expect(first.interruptions == 1)
        #expect(first.focusedSeconds == 30 * 60)
        #expect(first.span == 30 * 60 + 45)
        #expect(first.mainName == "Xcode")
        #expect(first.isDeep)
        #expect(!r.focusBlocks[1].isDeep)
        #expect(r.deepBlocks.count == 1)
        #expect(r.deepWorkSeconds == 30 * 60)
        #expect(r.days.first?.deepWorkSeconds == 1800.0)
    }

    @Test("A block that is mostly interruptions is not deep work, however long")
    func choppyBlockIsNotDeep() {
        // 40 minutes of 30 s work / 80 s Messages, over and over.
        let steps = (0..<44).map { i in (i % 2 == 0 ? Self.xcode : Self.messages, String?.none, i % 2 == 0 ? 30.0 : 80.0, 0.0) }
        let r = Self.report([Self.day(steps)])
        #expect(r.focusBlocks.count == 1)
        #expect(r.focusBlocks[0].span >= 25 * 60)
        #expect(!r.focusBlocks[0].isDeep)
        #expect(r.deepBlocks.isEmpty)
    }

    @Test("Slack is work but not focus: a short check interrupts a block, a long thread ends it")
    func messagingIsShallow() {
        let r = Self.report([Self.day([
            (Self.xcode, nil, 15 * 60, 0),
            (Self.slack, nil, 30, 0),          // a check: an interruption
            (Self.xcode, nil, 15 * 60, 0),
            (Self.slack, nil, 20 * 60, 0),     // a long thread: not deep work
        ])])
        #expect(r.focusBlocks.count == 1)
        #expect(r.focusBlocks[0].interruptions == 1)
        #expect(r.focusBlocks[0].focusedSeconds == 30 * 60)
        #expect(r.productiveSeconds == 30 * 60 + 30 + 20 * 60)
    }

    @Test("A trailing interruption does not stretch a block")
    func trailingInterruption() throws {
        let r = Self.report([Self.day([(Self.xcode, nil, 600, 0), (Self.messages, nil, 30, 0)])])
        let block = try #require(r.focusBlocks.first)
        #expect(block.span == 600)
        #expect(block.interruptions == 0)
    }

    @Test("Time away ends a block even if work resumes after it")
    func awayEndsBlock() {
        let r = Self.report([Self.day([(Self.xcode, nil, 20 * 60, 0), (Self.xcode, nil, 20 * 60, 10 * 60)])])
        #expect(r.focusBlocks.count == 2)
        #expect(r.deepBlocks.isEmpty)
        #expect(r.sittings == 2)
    }

    // MARK: Escapes, checks, rituals

    @Test("Escapes are direct jumps from work to something distracting")
    func escapes() throws {
        var steps: [(String, String?, Double, Double)] = []
        for _ in 0..<6 { steps += [(Self.xcode, nil, 300, 0), (Self.chrome, "reddit.com", 120, 0)] }
        steps += [(Self.messages, nil, 60, 0), (Self.chrome, "youtube.com", 60, 0)]   // Messages is not work: no escape
        let r = Self.report([Self.day(steps)])
        let top = try #require(r.escapes.first)
        #expect(top.from == "Xcode")
        #expect(top.to == "Reddit")
        #expect(top.count == 6)
        #expect(r.escapeDestinations.count == 1)
        let sentence = try #require(AttentionInsights.sentences(r).first { $0.kind == .escape })
        #expect(sentence.headline.contains("Reddit"))
    }

    @Test("Checks are short visits, counted per thing, and Finder is never one")
    func checks() throws {
        var steps: [(String, String?, Double, Double)] = []
        for _ in 0..<12 {
            steps += [(Self.xcode, nil, 100, 0), (Self.slack, nil, 20, 0), ("com.apple.finder", nil, 10, 0)]
        }
        var day = Self.day(steps)
        day.apps["com.apple.finder"] = AppUsage(name: "Finder")
        let r = Self.report([day])
        let top = try #require(r.checks.first)
        #expect(top.name == "Slack")
        #expect(top.count == 12)
        #expect(top.averageSeconds == 20)
        #expect(!r.checks.contains { $0.name == "Finder" })
        #expect(!r.checks.contains { $0.name == "Xcode" })
        let sentence = try #require(AttentionInsights.sentences(r).first { $0.kind == .checking })
        #expect(sentence.headline.hasPrefix("You checked Slack 12 times, for 20 seconds on average"))
    }

    @Test("First distraction and the day's opener are read per day")
    func rituals() throws {
        let days = (0..<3).map { offset in
            Self.day([(Self.slack, nil, 120, 0), (Self.xcode, nil, 360, 0), (Self.chrome, "reddit.com", 300, 0)],
                     start: Self.nine.addingTimeInterval(Double(offset) * 86_400))
        }
        let r = Self.report(days)
        #expect(r.measuredDays == 3)
        #expect(r.minutesToFirstDistraction == [8, 8, 8])
        #expect(r.openers == ["Slack", "Slack", "Slack"])
        let s = AttentionInsights.sentences(r)
        #expect(s.contains { $0.kind == .opener && $0.headline == "Most days start with Slack." })
        #expect(s.contains { $0.kind == .firstDistraction && $0.headline.contains("8m after you sit down, usually Reddit") })
    }

    @Test("Late-night time is the hours from 11 PM to 4 AM")
    func lateNight() {
        let late = Self.nine.addingTimeInterval(14 * 3600)   // 11 PM
        let r = Self.report([Self.day([(Self.chrome, "youtube.com", 45 * 60, 0)], start: late)])
        #expect(r.lateNightSeconds == 45 * 60)
        #expect(AttentionInsights.sentences(r).contains { $0.kind == .lateNight })
    }

    // MARK: Sentences

    @Test("The switching sentence states the rate, the interval and the evidence")
    func switchingSentence() throws {
        let steps = (0..<60).map { i in (i % 2 == 0 ? Self.xcode : Self.slack, String?.none, 60.0, 0.0) }
        let r = Self.report([Self.day(steps)])
        let s = try #require(AttentionInsights.sentences(r).first { $0.kind == .switching })
        #expect(s.headline.hasPrefix("You switch what's in front of you about 59 times an hour, once every 1 minute 1 second."))
        #expect(s.evidence?.contains("59 switches across 1h at the keyboard") == true)
    }

    @Test("Work with no 25-minute stretch says so")
    func fragmentedWork() throws {
        var steps: [(String, String?, Double, Double)] = []
        for _ in 0..<8 { steps += [(Self.xcode, nil, 10 * 60, 0), (Self.chrome, "youtube.com", 3 * 60, 0)] }
        let r = Self.report([Self.day(steps)])
        let s = try #require(AttentionInsights.sentences(r).first { $0.kind == .deepWork })
        #expect(s.headline.hasPrefix("No 25-minute stretch of deep work this week, though 1h 20m went to work."))
    }

    @Test("Nothing is said about an empty range")
    func emptyRange() {
        #expect(AttentionInsights.sentences(Self.report([])).isEmpty)
        #expect(AttentionInsights.sentences(Self.report([UsageDay(day: "2027-01-15")])).isEmpty)
    }
}
