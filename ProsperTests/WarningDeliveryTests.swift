import Foundation
import Testing
@testable import Prosper

/// Warnings are scheduled and delivered by pieces nobody sees until they go
/// wrong: a monitor installed with nothing to count, a monitor reset on every
/// launch, or the same rung arriving twice in a day (QA-9).
struct WarningDeliveryTests {

    // MARK: - Helpers

    /// A throwaway defaults domain per test, so nothing leaks between runs.
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WarningDeliveryTests.\(UUID().uuidString)")!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func request(
        enabled: Bool = true,
        threshold: Int = 30,
        apps: Int = 0,
        categories: Int = 0,
        webTokens: Int = 0,
        typed: Int = 0,
        selection: Data? = nil
    ) -> WasteMonitorRequest {
        WasteMonitorRequest(
            enabled: enabled,
            thresholdMinutes: threshold,
            applicationTokenCount: apps,
            categoryTokenCount: categories,
            webDomainTokenCount: webTokens,
            typedDomainCount: typed,
            selectionData: selection
        )
    }

    // MARK: - Delivery ledger

    @Test("The same rung on the same day is delivered once")
    func sameDaySameRungSuppressed() {
        let ledger = WarningDeliveryLedger(defaults: freshDefaults(), calendar: calendar)
        #expect(ledger.claim(.nudge, thresholdMinutes: 30, on: date(24, hour: 9)))
        #expect(ledger.hasDelivered(.nudge, thresholdMinutes: 30, on: date(24, hour: 15)))
        #expect(!ledger.claim(.nudge, thresholdMinutes: 30, on: date(24, hour: 15)))
    }

    @Test("A new day starts clean")
    func newDayAllowed() {
        let ledger = WarningDeliveryLedger(defaults: freshDefaults(), calendar: calendar)
        #expect(ledger.claim(.firm, thresholdMinutes: 60, on: date(24, hour: 22)))
        #expect(!ledger.hasDelivered(.firm, thresholdMinutes: 60, on: date(25, hour: 8)))
        #expect(ledger.claim(.firm, thresholdMinutes: 60, on: date(25, hour: 8)))
    }

    @Test("A changed threshold is a different warning")
    func differentThresholdAllowed() {
        let ledger = WarningDeliveryLedger(defaults: freshDefaults(), calendar: calendar)
        #expect(ledger.claim(.nudge, thresholdMinutes: 30, on: date(24, hour: 9)))
        #expect(ledger.claim(.nudge, thresholdMinutes: 45, on: date(24, hour: 10)))
    }

    @Test("Each rung is tracked on its own")
    func differentLevelAllowed() {
        let ledger = WarningDeliveryLedger(defaults: freshDefaults(), calendar: calendar)
        #expect(ledger.claim(.nudge, thresholdMinutes: 30, on: date(24, hour: 9)))
        #expect(ledger.claim(.firm, thresholdMinutes: 60, on: date(24, hour: 10)))
        #expect(!ledger.claim(.nudge, thresholdMinutes: 30, on: date(24, hour: 11)))
    }

    @Test("Clearing forgets today's deliveries")
    func clearForgets() {
        let ledger = WarningDeliveryLedger(defaults: freshDefaults(), calendar: calendar)
        ledger.claim(.intervention, thresholdMinutes: 90, on: date(24, hour: 9))
        ledger.clear()
        #expect(ledger.claim(.intervention, thresholdMinutes: 90, on: date(24, hour: 10)))
    }

    // MARK: - Fingerprint

    @Test("Equal inputs give equal fingerprints")
    func fingerprintEqual() {
        let data = Data(#"{"applicationTokens":[{"data":"AAA"}],"includeEntireCategory":false}"#.utf8)
        #expect(request(apps: 1, selection: data).fingerprint == request(apps: 1, selection: data).fingerprint)
    }

    /// Token sets are Swift `Set`s, encoded in a different order per process;
    /// the same list must not look new on every launch.
    @Test("Token order and key order do not change the fingerprint")
    func fingerprintIgnoresOrder() {
        let a = Data(#"{"applicationTokens":[{"data":"AAA"},{"data":"BBB"}],"categoryTokens":[]}"#.utf8)
        let b = Data(#"{"categoryTokens":[],"applicationTokens":[{"data":"BBB"},{"data":"AAA"}]}"#.utf8)
        #expect(request(apps: 2, selection: a).fingerprint == request(apps: 2, selection: b).fingerprint)
    }

    @Test("Any change to enabled, selection or threshold changes the fingerprint")
    func fingerprintDiffers() {
        let data = Data(#"{"applicationTokens":[{"data":"AAA"}]}"#.utf8)
        let other = Data(#"{"applicationTokens":[{"data":"CCC"}]}"#.utf8)
        let base = request(apps: 1, selection: data).fingerprint
        #expect(request(enabled: false, apps: 1, selection: data).fingerprint != base)
        #expect(request(threshold: 35, apps: 1, selection: data).fingerprint != base)
        #expect(request(apps: 1, selection: other).fingerprint != base)
        #expect(request(apps: 1, selection: nil).fingerprint != base)
    }

    @Test("The fingerprint store round-trips and clears")
    func recordRoundTrip() {
        let record = WasteMonitorRecord(defaults: freshDefaults())
        #expect(record.fingerprint == nil)
        record.fingerprint = "v2|1|30|x"
        record.failure = "Warnings aren't running"
        #expect(record.fingerprint == "v2|1|30|x")
        #expect(record.failure == "Warnings aren't running")
        record.clear()
        #expect(record.fingerprint == nil)
        #expect(record.failure == nil)
    }

    // MARK: - Should schedule

    @Test("Typed sites alone never schedule a monitor")
    func typedDomainsOnlyDoesNotSchedule() {
        #expect(!request(typed: 5).shouldSchedule)
    }

    @Test("Any picker token schedules a monitor", arguments: [
        (1, 0, 0), (0, 1, 0), (0, 0, 1), (3, 2, 1),
    ])
    func tokensSchedule(_ apps: Int, _ categories: Int, _ webTokens: Int) {
        #expect(request(apps: apps, categories: categories, webTokens: webTokens).shouldSchedule)
        #expect(request(apps: apps, categories: categories, webTokens: webTokens, typed: 4).shouldSchedule)
    }

    @Test("Warnings off, or no threshold, never schedule")
    func disabledDoesNotSchedule() {
        #expect(!request(enabled: false, apps: 3).shouldSchedule)
        #expect(!request(threshold: 0, apps: 3).shouldSchedule)
    }
}
