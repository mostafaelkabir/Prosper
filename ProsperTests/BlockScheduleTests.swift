import Testing
import Foundation
import FamilyControls
@testable import Prosper

/// The timers that end a block, and the checks that run before one starts.
/// A wrong answer here is either a block that never lifts or one that lifts
/// early — the two failures the product promise rules out (QA-9).
struct BlockScheduleTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let minute: TimeInterval = 60

    // MARK: - UnblockSchedule.plan

    @Test("A normal block gets an exact timer from start to end")
    func primaryCoversTheBlock() {
        let end = now.addingTimeInterval(60 * minute)
        let plan = UnblockSchedule.plan(from: now, to: end)
        #expect(plan.primary == DateInterval(start: now, end: end))
    }

    @Test("The safety timer closes after the block ends, never before")
    func safetyEndsAfterTheBlock() {
        for length: TimeInterval in [15, 16, 30, 60, 240, 1435] {
            let end = now.addingTimeInterval(length * minute)
            let plan = UnblockSchedule.plan(from: now, to: end)
            #expect(plan.safety.end >= end.addingTimeInterval(UnblockSchedule.safetyGrace))
        }
    }

    @Test("Every interval is long enough for iOS to accept it")
    func intervalsAreLegal() {
        for remaining: TimeInterval in [1, 5, 14, 15, 16, 45, 600, 1435] {
            let plan = UnblockSchedule.plan(from: now, to: now.addingTimeInterval(remaining * minute))
            #expect(plan.safety.duration >= UnblockSchedule.minimumSpan)
            if let primary = plan.primary {
                #expect(primary.duration >= UnblockSchedule.minimumSpan)
            }
        }
    }

    @Test("Under fifteen minutes left there is no primary timer, only the safety window")
    func shortRemainderSkipsPrimary() {
        let plan = UnblockSchedule.plan(from: now, to: now.addingTimeInterval(10 * minute))
        #expect(plan.primary == nil)
        #expect(plan.safety.start == now)
    }

    @Test("A long block's safety window stays short instead of spanning the day")
    func longBlockSafetyIsShort() {
        let end = now.addingTimeInterval(8 * 60 * minute)
        let plan = UnblockSchedule.plan(from: now, to: end)
        #expect(plan.safety.duration == UnblockSchedule.safetySpan)
        #expect(plan.safety.start > now)
    }

    @Test("Re-arming mid-block ends at the same moment as the original plan")
    func rearmKeepsTheEnd() {
        let end = now.addingTimeInterval(3 * 60 * minute)
        let later = now.addingTimeInterval(60 * minute)
        let original = UnblockSchedule.plan(from: now, to: end)
        let rearmed = UnblockSchedule.plan(from: later, to: end)
        #expect(rearmed.primary?.end == original.primary?.end)
        #expect(rearmed.safety.end == original.safety.end)
    }

    // MARK: - BlockingService.validate

    @Test("Nothing selected is refused")
    func emptySelectionRefused() {
        let error = BlockingService.validate(selection: FamilyActivitySelection(), domains: [], duration: 3600)
        #expect(error == .nothingSelected)
    }

    @Test("A typed site alone is a real block")
    func typedSiteIsEnough() {
        let error = BlockingService.validate(selection: FamilyActivitySelection(), domains: ["reddit.com"], duration: 3600)
        #expect(error == nil)
    }

    @Test("Anything under fifteen minutes is refused, fifteen exactly is fine")
    func minimumDuration() {
        let selection = FamilyActivitySelection()
        #expect(BlockingService.validate(selection: selection, domains: ["x.com"], duration: 14 * minute) == .tooShort)
        #expect(BlockingService.validate(selection: selection, domains: ["x.com"], duration: 15 * minute) == nil)
    }

    @Test("More sites than the filter holds is refused rather than silently cut")
    func siteCap() {
        let fifty = (1...50).map { "site\($0).com" }
        #expect(BlockingService.validate(selection: FamilyActivitySelection(), domains: fifty, duration: 3600) == nil)
        let error = BlockingService.validate(selection: FamilyActivitySelection(), domains: fifty + ["one-more.com"], duration: 3600)
        #expect(error == .tooManySites(51))
    }
}
