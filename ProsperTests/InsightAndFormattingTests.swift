import Testing
import Foundation
@testable import Prosper

private func minutes(_ m: Double) -> TimeInterval { m * 60 }

/// The insight engine speaks in plain sentences about the user's own usage. On
/// thin data, or about a browser, a confident sentence is a false one (QA-9).
struct InsightEngineTests {
    private func signals(total: Double, _ apps: [(String, Double, Int)]) -> InsightSignals {
        var s = InsightSignals()
        s.totalDuration = minutes(total)
        s.apps = apps.map { InsightSignals.App(name: $0.0, duration: minutes($0.1), pickups: $0.2) }
        return s
    }

    @Test("Under five minutes tracked there is nothing to say")
    func silentOnAlmostNothing() {
        #expect(InsightEngine.rank(signals(total: 4, [("Instagram", 4, 30)])).isEmpty)
    }

    @Test("Concentration needs 30 minutes tracked in total")
    func concentrationNeedsTotal() {
        let cards = InsightEngine.rank(signals(total: 29, [("YouTube", 25, 1)]))
        #expect(!cards.contains { $0.kind == .concentration })
    }

    @Test("Concentration needs 10 minutes in the app itself")
    func concentrationNeedsAppTime() {
        let under = InsightEngine.rank(signals(total: 30, [("YouTube", 9.9, 1)]))
        #expect(!under.contains { $0.kind == .concentration })

        let over = InsightEngine.rank(signals(total: 30, [("YouTube", 10, 1)]))
        #expect(over.contains { $0.kind == .concentration && $0.headline.hasPrefix("YouTube") })
    }

    @Test("A browser is never the concentration card", arguments: ["Safari", "Chrome", "Microsoft Edge", "Arc"])
    func browsersNeverConcentrate(browser: String) {
        let cards = InsightEngine.rank(signals(total: 120, [(browser, 100, 2), ("Notes", 5, 1)]))
        #expect(!cards.contains { $0.kind == .concentration })
        #expect(!cards.contains { $0.headline.contains(browser) && $0.evidence.contains("block") })
    }

    @Test("A non-browser whose name contains a browser word still can be")
    func lookalikeStillConcentrates() {
        let cards = InsightEngine.rank(signals(total: 60, [("Ledger Live", 40, 1)]))
        #expect(cards.contains { $0.kind == .concentration && $0.headline.hasPrefix("Ledger Live") })
    }

    @Test("The reflex card talks about pickups, never visits or opens")
    func reflexWording() throws {
        let cards = InsightEngine.rank(signals(total: 60, [("Instagram", 5, 18)]))
        let reflex = try #require(cards.first { $0.kind == .checkingReflex })
        #expect(reflex.headline == "Instagram was the first app after 18 pickups.")
        let text = (reflex.headline + " " + reflex.evidence).lowercased()
        #expect(!text.contains("visit"))
        #expect(!text.contains("opened"))
        #expect(!text.contains(" each "))
        #expect(!text.contains("s each"))
    }

    @Test("A reflex needs at least ten pickups")
    func reflexNeedsPickups() {
        let cards = InsightEngine.rank(signals(total: 60, [("Instagram", 2, 9)]))
        #expect(!cards.contains { $0.kind == .checkingReflex })
    }

    @Test("At most three cards, strongest first")
    func rankedAndCapped() {
        let cards = InsightEngine.rank(signals(total: 120, [
            ("Instagram", 5, 40), ("TikTok", 90, 3), ("Reddit", 2, 12), ("Notes", 20, 1),
        ]))
        #expect(!cards.isEmpty)
        #expect(cards.count <= 3)
        #expect(cards.map(\.score) == cards.map(\.score).sorted(by: >))
        #expect(Set(cards.map(\.kind)) == [.checkingReflex, .concentration])
    }
}

struct HourlyUsageTests {
    @Test("No peak hour when nothing was used")
    func peakHourNilWhenEmpty() {
        #expect(HourlyUsage().peakHour == nil)
        var zeroed = HourlyUsage()
        zeroed.cells = [HourlyUsage.Cell(day: Calendar.current.startOfDay(for: .now), hour: 9, duration: 0)]
        #expect(zeroed.peakHour == nil)
    }

    @Test("The peak is the busiest hour summed across days")
    func peakHourAcrossDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var usage = HourlyUsage()
        usage.cells = [
            .init(day: yesterday, hour: 8, duration: 600),
            .init(day: today, hour: 8, duration: 600),
            .init(day: today, hour: 21, duration: 900),
        ]
        #expect(usage.peakHour == 8)
    }

    @Test("The grid draws a row for every day it counts — 30 for a month")
    func gridCoversEveryCountedDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let month = (0..<30).map { calendar.date(byAdding: .day, value: -$0, to: today)! }.reversed()
        var usage = HourlyUsage()
        usage.coveredDays = Array(month)
        usage.days = [today]
        usage.cells = [.init(day: today, hour: 20, duration: 600)]
        #expect(usage.gridDays.count == 30)
        #expect(usage.gridDays.first == month.first)
        #expect(usage.gridDays.last == today)

        // Every day with a cell is on the grid, so the header's total is drawn.
        let oldest = month.first!
        usage.cells.append(.init(day: oldest, hour: 7, duration: 300))
        #expect(usage.cells.allSatisfy { usage.gridDays.contains($0.day) })
    }

    @Test("A week grid is never shorter than seven rows")
    func weekGridHasSevenRows() {
        let today = Calendar.current.startOfDay(for: .now)
        var usage = HourlyUsage()
        usage.days = [today]
        usage.coveredDays = [today]
        #expect(usage.gridDays.count == 7)
    }

    @Test("Hour labels", arguments: [(0, "12a"), (1, "1a"), (11, "11a"), (12, "12p"), (13, "1p"), (23, "11p")])
    func hourLabels(hour: Int, label: String) {
        #expect(hourLabel(hour) == label)
    }
}

struct UsageFormattingTests {
    @Test("Durations read as the app shows them", arguments: [
        (0.0, "0m"), (30.0, "<1m"), (60.0, "1m"), (3600.0, "1h"), (8040.0, "2h 14m"),
    ])
    func usageFormatted(seconds: TimeInterval, text: String) {
        #expect(seconds.usageFormatted == text)
    }
}

/// The report ranges are "today", "last 7 days" and "last 30 days". If a start
/// date lands off local midnight or in the future, a range quietly drops a day
/// or shows nothing (QA-9).
struct UsageReportFilterTests {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("7- and 30-day ranges start at local midnight 6 and 29 days back", arguments: [
        ("America/New_York", "2026-09-24T15:30:00Z"),
        ("America/New_York", "2026-03-10T12:00:00Z"),   // just after the spring-forward change
        ("Europe/London", "2026-10-26T00:30:00Z"),      // just after fall-back
        ("Asia/Tokyo", "2026-09-24T23:59:00Z"),
        ("Pacific/Auckland", "2026-04-06T10:00:00Z"),
    ])
    func startsAtLocalMidnight(zone: String, iso: String) {
        let calendar = calendar(zone)
        let now = date(iso)
        let todayStart = calendar.startOfDay(for: now)
        for (daysBack, expected) in [(0, 0), (UsageReportFilter.sevenDaysBack, 6), (UsageReportFilter.thirtyDaysBack, 29)] {
            let start = UsageReportFilter.startDate(daysBack: daysBack, now: now, calendar: calendar)
            #expect(start == calendar.startOfDay(for: start))
            #expect(calendar.dateComponents([.day], from: start, to: todayStart).day == expected)
            #expect(start <= now)
        }
    }

    @Test("A range never starts in the future")
    func neverInTheFuture() {
        let now = Date.now
        #expect(UsageReportFilter.startDate(daysBack: 0, now: now) <= now)
        #expect(UsageReportFilter.startDate(daysBack: -3, now: now) <= now)
        #expect(UsageReportFilter.startDate(daysBack: 6) == Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)))
    }
}
