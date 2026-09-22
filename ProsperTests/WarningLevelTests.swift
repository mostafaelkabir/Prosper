import Testing
import DeviceActivity
@testable import Prosper

/// The warning ladder decides when each rung fires and what it says. It ships
/// silently — nothing surfaces a wrong threshold until a user is nudged at the
/// wrong time, or the intervention quotes a number that is not theirs (REL-15).
struct WarningLevelTests {

    // MARK: - Thresholds

    @Test("Each rung is its multiple of the user's base threshold")
    func thresholdsScaleWithBase() {
        #expect(WarningLevel.nudge.thresholdMinutes(base: 30) == 30)
        #expect(WarningLevel.firm.thresholdMinutes(base: 30) == 60)
        #expect(WarningLevel.intervention.thresholdMinutes(base: 30) == 90)
    }

    @Test("The ladder holds at the ends of the range the UI allows (5…240)")
    func thresholdsAtRangeBounds() {
        #expect(WarningLevel.intervention.thresholdMinutes(base: 5) == 15)
        #expect(WarningLevel.intervention.thresholdMinutes(base: 240) == 720)
    }

    @Test("Rungs are strictly increasing, so a lower one cannot fire after a higher")
    func thresholdsIncrease() {
        for base in [5, 17, 30, 90, 240] {
            let minutes = WarningLevel.allCases.map { $0.thresholdMinutes(base: base) }
            #expect(minutes == minutes.sorted())
            #expect(Set(minutes).count == minutes.count)
        }
    }

    /// InterventionView divides back by the level to show "your threshold", so
    /// the round trip has to land on the number the user actually set.
    @Test("The intervention's displayed threshold recovers the user's own number")
    func interventionDisplayedThresholdRoundTrips() {
        for base in [5, 30, 45, 240] {
            let fired = WarningLevel.intervention.thresholdMinutes(base: base)
            #expect(fired / WarningLevel.intervention.rawValue == base)
        }
    }

    // MARK: - Event identity

    @Test("Every rung maps back from its event name")
    func eventNameRoundTrip() {
        for level in WarningLevel.allCases {
            #expect(WarningLevel.level(for: level.eventName) == level)
        }
    }

    @Test("Rungs do not share an event name")
    func eventNamesAreDistinct() {
        let names = Set(WarningLevel.allCases.map(\.eventName.rawValue))
        #expect(names.count == WarningLevel.allCases.count)
    }

    /// Level 1 deliberately keeps the original name so a schedule installed by
    /// an earlier build still matches after an in-place upgrade. Renaming it
    /// would silently stop nudges for existing users.
    @Test("Level 1 keeps its legacy event name")
    func legacyEventName() {
        #expect(WarningLevel.nudge.eventName.rawValue == "prosper.waste.threshold")
    }

    @Test("An unrelated event name maps to no rung")
    func unknownEventName() {
        #expect(WarningLevel.level(for: DeviceActivityEvent.Name("prosper.unblock")) == nil)
        #expect(WarningLevel.level(for: DeviceActivityEvent.Name("")) == nil)
    }

    // MARK: - Duration text

    @Test("Durations read the way a person would say them", arguments: [
        (0, "0m"), (1, "1m"), (45, "45m"), (59, "59m"),
        (60, "1h"), (120, "2h"), (90, "1h 30m"), (61, "1h 1m"), (725, "12h 5m"),
    ])
    func durationText(_ input: Int, _ expected: String) {
        #expect(WarningLevel.durationText(input) == expected)
    }

    @Test("A whole number of hours never shows a stray 0m")
    func wholeHoursHaveNoMinutes() {
        for hours in 1...12 {
            #expect(WarningLevel.durationText(hours * 60) == "\(hours)h")
        }
    }

    // MARK: - Copy

    @Test("The ladder summary names all three rungs in order")
    func ladderText() {
        let text = WarningLevel.ladderText(base: 30)
        #expect(text == "Nudge at 30m, firm reminder at 1h, intervention at 1h 30m.")
    }

    @Test("Every rung has a title and a body that quotes the elapsed time")
    func notificationCopy() {
        for level in WarningLevel.allCases {
            #expect(!level.notificationTitle.isEmpty)
            let body = level.notificationBody(minutes: 90)
            #expect(body.contains("1h 30m"))
        }
    }

    @Test("The stored reason names the minutes and the level")
    func triggerReason() {
        let reason = WarningLevel.firm.triggerReason(minutes: 60)
        #expect(reason.contains("60"))
        #expect(reason.contains("level 2"))
    }
}
