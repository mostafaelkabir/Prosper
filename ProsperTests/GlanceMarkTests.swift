import Testing
import CoreGraphics
@testable import Prosper

/// The Stolen Glance reveal (DS-10). The timeline is a pure function of time,
/// so each beat can be checked at the moment it should land, and the last
/// frame must be the printed mark, or the reveal jumps when it hands over.
struct GlanceMarkTests {

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.02) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test func startsAsADotOnAShutEye() {
        let s = GlanceTimeline.state(at: 0)
        #expect(s.draw == 0)
        #expect(s.lid == -1)
        #expect(s.key == 0)
        #expect(s.word == 0)
        #expect(s.blur == 6)
    }

    @Test func endsOnTheRestingMark() {
        #expect(GlanceTimeline.state(at: GlanceTimeline.duration) == .rest)
        #expect(GlanceTimeline.state(at: 10) == .rest)
    }

    @Test func lastFrameHandsOverWithoutAJump() {
        let s = GlanceTimeline.state(at: GlanceTimeline.duration - 0.016)
        let rest = GlanceState.rest
        #expect(near(s.lid, rest.lid))
        #expect(near(s.gazeY, rest.gazeY))
        #expect(s.gazeX == 0)
        #expect(near(s.key, 1))
        #expect(near(s.word, 1))
        #expect(s.halo < 0.02)
        #expect(s.draw == 1 && s.blur == 0)
    }

    @Test func eyeIsDrawnBeforeItOpens() {
        let s = GlanceTimeline.state(at: 0.6)
        #expect(s.draw == 1)
        #expect(s.lid == -1)
    }

    @Test func theGlanceGoesLeftThenRight() {
        #expect(GlanceTimeline.state(at: 1.40).gazeX < -20)
        #expect(GlanceTimeline.state(at: 1.70).gazeX > 20)
        // Still a round pupil while it looks around.
        #expect(GlanceTimeline.state(at: 1.70).key == 0)
    }

    @Test func caughtShutsTheEyeAndResetsTheGaze() {
        let shut = GlanceTimeline.state(at: 1.889)
        #expect(shut.lid < -0.9)
        let reopening = GlanceTimeline.state(at: 1.9)
        #expect(reopening.gazeX == 0)
        #expect(reopening.gazeY == GlanceState.rest.gazeY)
    }

    @Test func pupilBecomesAKeyhole() {
        #expect(GlanceTimeline.state(at: 1.94).key == 0)
        #expect(GlanceTimeline.state(at: 2.31).key == 1)
    }

    @Test func haloLeavesOnce() {
        #expect(GlanceTimeline.state(at: 2.04).halo == 0)
        #expect(GlanceTimeline.state(at: 2.06).halo > 0.9)
        #expect(GlanceTimeline.state(at: 2.71).halo == 0)
    }

    @Test func springSettlesAndOvershootsALittle() {
        #expect(GlanceTimeline.spring(0) == 0)
        #expect(GlanceTimeline.spring(1) == 1)
        let peak = stride(from: 0.0, through: 1.0, by: 0.01).map { GlanceTimeline.spring(CGFloat($0)) }.max()!
        #expect(peak > 1.1 && peak < 1.2)
    }

    @Test func keyholeSitsInsideTheIris() {
        let r = GlanceGeometry.irisRadius
        let iris = CGRect(x: 100 - r, y: 100 - r, width: r * 2, height: r * 2)
        #expect(iris.contains(GlanceGeometry.stem(key: 1).boundingBoxOfPath))
        #expect(iris.contains(GlanceGeometry.pupil(key: 1)))
    }

    @Test func shutEyeShowsNoIris() {
        // Shut, the opening's top edge meets its bottom edge: nothing shows.
        let shut = GlanceGeometry.opening(-1)
        #expect(!shut.contains(CGPoint(x: 100, y: 130)))
        #expect(GlanceGeometry.opening(GlanceState.rest.lid).contains(CGPoint(x: 100, y: 100)))
    }

    // MARK: Lock start (DS-11)

    @Test func sealStartsWideOpenWithARoundPupil() {
        let s = GlanceTimeline.seal(at: 0)
        #expect(s.lid == 1)
        #expect(s.key == 0)
        #expect(s.draw == 1 && s.word == 1)
    }

    @Test func sealGlancesAsideFirst() {
        #expect(GlanceTimeline.seal(at: 0.2).gazeX < -13)
    }

    @Test func sealShutsOnTheThud() {
        #expect(GlanceTimeline.seal(at: GlanceTimeline.sealShut - 0.001).lid < -0.9)
        #expect(GlanceTimeline.seal(at: GlanceTimeline.sealShut + 0.01).gazeX == 0)
    }

    @Test func sealSettlesOnTheRestingMark() {
        #expect(GlanceTimeline.seal(at: 0.85) == .rest)
        #expect(GlanceTimeline.seal(at: GlanceTimeline.sealDuration) == .rest)
        // It must finish inside the 2 s the sheet stays up.
        #expect(GlanceTimeline.sealDuration < 2)
    }
}
