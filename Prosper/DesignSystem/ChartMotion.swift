import SwiftUI

// Motion for the numbers screens: Insights and the report views it hosts
// (UX-30). Each piece follows a named 60fps.design shot; the content and look
// are our own. Everything plays once, when the view appears, and shows the
// final state at once under Reduce Motion.
//
// A range or section switch gives the hosted report a fresh identity
// (`StatsView.reportID`), so these play again on every switch, the way
// GrowPal's stats replay when you tap Week / Month / Year.

enum ChartMotion {
    /// Bars rise from the baseline: medium, ease-out, a touch of spring
    /// (GrowPal stats, 60fps.design/shots/growpal-stats-animation).
    static let grow = Animation.smooth(duration: 0.6, extraBounce: 0.04)

    /// Cards lift in one after another with a clear beat between them
    /// (Alma's score reveal, 60fps.design/shots/alma-nutrition-score-progress-animation).
    static func rise(_ order: Int) -> Animation {
        .easeOut(duration: 0.4).delay(0.08 * Double(min(order, 8)))
    }

    /// Grid cells fill in, scaling up a little as they fade in
    /// (Unfold's calendar intro, 60fps.design/shots/unfold-schedule-posts-intro-animation).
    static func cell(_ order: Int) -> Animation {
        .smooth(duration: 0.45, extraBounce: 0.06).delay(0.025 * Double(order))
    }

    /// The big number counts up while the bars grow (GrowPal stats).
    static let count = Animation.easeOut(duration: 0.8)
}

// MARK: - Appearing

/// Flips to true on the first appear. Views that reveal themselves read this
/// instead of each keeping their own `onAppear` dance.
///
/// With an `animation`, the flip happens inside `withAnimation`, for values
/// that are not a modifier (Swift Charts bar heights). Without one, the
/// modifiers below animate their own part, scoped so a bar inside a card that
/// is lifting in moves with the card instead of on its own clock.
private struct AppearedModifier: ViewModifier {
    @Binding var appeared: Bool
    let animation: Animation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                // The next run loop, so the first frame is drawn at rest and
                // the change is animated rather than folded into the insert.
                DispatchQueue.main.async {
                    if let animation {
                        withAnimation(animation) { appeared = true }
                    } else {
                        appeared = true
                    }
                }
            }
        }
    }
}

extension View {
    /// Sets `appeared` once this view is on screen. See `AppearedModifier`.
    func onFirstAppear(_ appeared: Binding<Bool>, animation: Animation? = nil) -> some View {
        modifier(AppearedModifier(appeared: appeared, animation: animation))
    }

    /// Lifts the view in as one card of a staggered stack (`ChartMotion.rise`).
    func riseIn(_ shown: Bool, order: Int = 0) -> some View {
        modifier(RiseIn(shown: shown, order: order))
    }

    /// Grows the view from its leading edge (horizontal bars) or its bottom
    /// (columns). Used for bars drawn as shapes; Swift Charts bars grow
    /// through their values instead.
    func growIn(_ shown: Bool, axis: Axis = .horizontal, delay: Double = 0) -> some View {
        modifier(GrowIn(shown: shown, axis: axis, delay: delay))
    }
}

private struct RiseIn: ViewModifier {
    let shown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content.animation(reduceMotion ? nil : ChartMotion.rise(order)) {
            $0.opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 14)
        }
    }
}

private struct GrowIn: ViewModifier {
    let shown: Bool
    let axis: Axis
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let scale: CGFloat = shown || reduceMotion ? 1 : 0.001
        content.animation(reduceMotion ? nil : ChartMotion.grow.delay(delay)) {
            $0.scaleEffect(x: axis == .horizontal ? scale : 1,
                           y: axis == .vertical ? scale : 1,
                           anchor: axis == .horizontal ? .leading : .bottom)
        }
    }
}

// MARK: - Counting up

/// A number that counts up to its value when it first appears, frame by
/// frame, in tabular digits so the width holds still. VoiceOver reads the
/// final value only.
struct CountUpText: View, @preconcurrency Animatable {
    /// The value being drawn right now; animated from 0 to the target.
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value)).monospacedDigit()
    }
}

/// Hosts a `CountUpText`, starting it at zero and counting to `target`.
struct CountUp: View {
    let target: Double
    let format: (Double) -> String

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CountUpText(value: shown || reduceMotion ? target : 0, format: format)
            .onFirstAppear($shown, animation: ChartMotion.count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(format(target))
    }
}

extension TimeInterval {
    /// `usageFormatted`, rounded down to whole minutes so a counting value
    /// steps through "1h 58m, 1h 59m" instead of flickering seconds.
    var countingFormatted: String {
        (floor(self / 60) * 60).usageFormatted
    }
}

// MARK: - A ring that draws itself

/// A share of a whole, drawn clockwise from twelve o'clock on a faint track
/// (Alma's score ring, 60fps.design/shots/alma-nutrition-score-progress-animation).
struct ShareRing: View {
    let fraction: Double
    var color: Color = ProsperColor.accent
    var lineWidth: CGFloat = 7

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(ProsperColor.surface2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown || reduceMotion ? max(0.02, min(1, fraction)) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onFirstAppear($shown, animation: .easeOut(duration: 0.8).delay(0.15))
        .accessibilityHidden(true)
    }
}
