import CoreGraphics
import Foundation

/// The Stolen Glance mark (DS-10): an eye under a lowered lid whose pupil turns
/// into a keyhole. Shapes and the launch timeline only, no colour and no
/// SwiftUI, so `scripts/make-app-icon.swift` compiles this file as it is and
/// the icon can never drift from the mark the app draws (`GlanceMark`).
/// `docs/design/stolen-glance-logo/mark.js` is the web copy of these numbers.
///
/// Everything lives in a 200 x 200 box. The eye's corners sit at (28,100) and
/// (172,100). Each lid is a filled, tapered stroke: thick in the middle, a
/// point at each corner. The lower lid is fixed; the upper lid follows `lid`:
/// 1 is wide open, 0.8 is the mark at rest, -1 is shut, where it lies on the
/// lower lid and the eye reads as a lowered gaze.
nonisolated enum GlanceGeometry {
    static let box: CGFloat = 200
    static let left = CGPoint(x: 28, y: 100)
    static let right = CGPoint(x: 172, y: 100)
    static let centre: CGFloat = 100
    static let lowerControlY: CGFloat = 156
    static let span: CGFloat = 56
    /// Half-thickness of each lid, in control-point units (15 pt and 8 pt at the middle).
    static let upperHalf: CGFloat = 10
    static let lowerHalf: CGFloat = 5.5
    static let irisRadius: CGFloat = 43
    /// The lid gradient runs corner to corner, violet to cyan to mint.
    static let gradientStart = CGPoint(x: 28, y: 58)
    static let gradientEnd = CGPoint(x: 172, y: 142)
    static let gradientStops: [CGFloat] = [0, 0.52, 1]

    static func upperControlY(_ lid: CGFloat) -> CGFloat { centre - span * lid }

    /// An eye-shaped band between two curves through both corners.
    static func band(top: CGFloat, bottom: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: left)
        p.addCurve(to: right, control1: CGPoint(x: 58, y: top), control2: CGPoint(x: 142, y: top))
        p.addCurve(to: left, control1: CGPoint(x: 142, y: bottom), control2: CGPoint(x: 58, y: bottom))
        p.closeSubpath()
        return p
    }

    static func upperLid(_ lid: CGFloat) -> CGPath {
        let y = upperControlY(lid)
        return band(top: y - upperHalf, bottom: y + upperHalf)
    }

    static var lowerLid: CGPath { band(top: lowerControlY - lowerHalf, bottom: lowerControlY + lowerHalf) }

    /// The opening between the lids' inner edges, where the iris shows.
    static func opening(_ lid: CGFloat) -> CGPath {
        let top = min(upperControlY(lid) + upperHalf, lowerControlY - lowerHalf)
        return band(top: top, bottom: lowerControlY - lowerHalf)
    }

    /// The eye's outline through the middle of both lids, for the halo.
    static func outline(_ lid: CGFloat) -> CGPath {
        band(top: upperControlY(lid), bottom: lowerControlY)
    }

    /// The pupil is round at `key` 0 and the head of a keyhole at `key` 1.
    static func pupil(key: CGFloat) -> CGRect {
        let cy = 100 - 7 * key, r = 13.5 - 2 * key
        return CGRect(x: 100 - r, y: cy - r, width: r * 2, height: r * 2)
    }

    /// The keyhole's stem, grown downward from its top edge by `key`.
    static func stem(key: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 95, y: 97))
        p.addLine(to: CGPoint(x: 105, y: 97))
        p.addLine(to: CGPoint(x: 108.6, y: 121))
        p.addQuadCurve(to: CGPoint(x: 105.6, y: 124.5), control: CGPoint(x: 109, y: 124.5))
        p.addLine(to: CGPoint(x: 94.4, y: 124.5))
        p.addQuadCurve(to: CGPoint(x: 91.4, y: 121), control: CGPoint(x: 91, y: 124.5))
        p.closeSubpath()
        var grow = CGAffineTransform(translationX: 100, y: 97)
            .scaledBy(x: 1, y: max(0.0001, key))
            .translatedBy(x: -100, y: -97)
        return p.copy(using: &grow) ?? p
    }

    /// Moves and scales the eyeball (iris, pupil, stem) for gaze and size.
    static func eyeball(_ s: GlanceState) -> CGAffineTransform {
        CGAffineTransform(translationX: s.gazeX + 100, y: s.gazeY + 100)
            .scaledBy(x: s.iris, y: s.iris)
            .translatedBy(x: -100, y: -100)
    }

    /// The halo leaves the eye and fades: scale 1.24 at `halo` 0, 1 at `halo` 1.
    static func haloScale(_ halo: CGFloat) -> CGFloat { 1 + 0.24 * (1 - halo) }

    /// Draw-in reveals the lids from the middle outward: a dot, then the line.
    static func reveal(_ draw: CGFloat) -> CGRect {
        CGRect(x: 100 - 78 * draw, y: 0, width: max(0.001, 156 * draw), height: box)
    }
}

/// One frame of the mark. `rest` is the mark as it is printed.
nonisolated struct GlanceState: Equatable, Sendable {
    var lid: CGFloat = 0.8
    var gazeX: CGFloat = 0
    var gazeY: CGFloat = 5
    var iris: CGFloat = 1
    var key: CGFloat = 1
    var draw: CGFloat = 1
    var blur: CGFloat = 0
    var halo: CGFloat = 0
    /// The name beside the mark: 0 hidden, 1 shown.
    var word: CGFloat = 1

    static let rest = GlanceState()
}

/// The launch reveal, 2.8 s, as a pure function of time so it can be tested
/// and scrubbed. Each beat follows a named 60fps shot:
/// - Seed, 0-560 ms: a dot draws outward into a closed eye while a blur clears
///   (Tiimo Splash Logo Animation; Apple Arcade Splash Logo Animation).
/// - Open, 640-1120 ms: the lid lifts on a spring, the iris rises behind it
///   (ClearPro Splash).
/// - The glance, 1220-1660 ms: the pupil darts left, then right. Our own beat.
/// - Caught, 1780-2180 ms: the lid snaps shut; the gaze resets behind it.
/// - Locked, 1950-2700 ms: the pupil becomes a keyhole and one halo leaves the
///   eye, the same close as `LockSeal`.
/// - Name, 2150-2800 ms: the name unmasks (Apple Arcade; Emphasis Get Started).
nonisolated enum GlanceTimeline {
    static let duration: TimeInterval = 2.8

    static func state(at seconds: TimeInterval) -> GlanceState {
        let t = seconds * 1000
        if t >= duration * 1000 { return .rest }
        var s = GlanceState.rest
        let rest = GlanceState.rest

        let d = outCubic(progress(t, 0, 560))
        s.draw = d
        s.blur = 6 * (1 - d)

        let o = progress(t, 640, 1120)
        s.lid = t < 640 ? -1 : lerp(-1, 1, spring(o))
        s.iris = t < 640 ? 0.7 : lerp(0.7, 1, outBack(o))

        let left = outQuart(progress(t, 1220, 1360))
        let right = outQuart(progress(t, 1500, 1660))
        s.gazeX = t < 1500 ? -22 * left : lerp(-22, 22, right)
        s.gazeY = 0

        if t >= 1780 {
            if t < 1890 {
                s.lid = lerp(1, -0.96, inQuad(progress(t, 1780, 1890)))
            } else {
                s.lid = lerp(-0.96, rest.lid, spring(progress(t, 1890, 2180)))
                s.gazeX = 0
                s.gazeY = rest.gazeY
            }
        }

        s.key = t < 1950 ? 0 : spring(progress(t, 1950, 2300))
        s.halo = t < 2050 ? 0 : 1 - outCubic(progress(t, 2050, 2700))
        s.word = outCubic(progress(t, 2150, 2800))
        return s
    }

    // MARK: Easing

    static func progress(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        CGFloat(max(0, min(1, (t - a) / (b - a))))
    }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }
    static func outCubic(_ p: CGFloat) -> CGFloat { 1 - pow(1 - p, 3) }
    static func outQuart(_ p: CGFloat) -> CGFloat { 1 - pow(1 - p, 4) }
    static func inQuad(_ p: CGFloat) -> CGFloat { p * p }
    static func outBack(_ p: CGFloat) -> CGFloat {
        let c: CGFloat = 1.6
        return 1 + (c + 1) * pow(p - 1, 3) + c * pow(p - 1, 2)
    }
    /// A damped spring, about 15% overshoot, settled at p = 1.
    static func spring(_ p: CGFloat) -> CGFloat {
        p >= 1 ? 1 : 1 - exp(-6.2 * p) * cos(10 * p)
    }
}
