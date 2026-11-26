import SwiftUI

/// The Stolen Glance mark drawn from `GlanceGeometry`, in the Aurora colours:
/// lids in the violet, cyan, mint gradient, the iris in ink with the keyhole cut
/// out so the background shows through. Follows light and dark.
struct GlanceMark: View {
    var state: GlanceState = .rest

    var body: some View {
        Canvas { context, size in
            Self.draw(state, in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func draw(_ s: GlanceState, in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let unit = side / GlanceGeometry.box
        context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        context.scaleBy(x: unit, y: unit)

        let lids = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: ProsperColor.accent, location: GlanceGeometry.gradientStops[0]),
                .init(color: ProsperColor.rest, location: GlanceGeometry.gradientStops[1]),
                .init(color: ProsperColor.productive, location: GlanceGeometry.gradientStops[2]),
            ]),
            startPoint: GlanceGeometry.gradientStart,
            endPoint: GlanceGeometry.gradientEnd
        )

        if s.halo > 0.001 {
            var halo = context
            let k = GlanceGeometry.haloScale(s.halo)
            halo.translateBy(x: 100, y: 100)
            halo.scaleBy(x: k, y: k)
            halo.translateBy(x: -100, y: -100)
            halo.opacity = 0.6 * s.halo
            halo.stroke(Path(GlanceGeometry.outline(GlanceState.rest.lid)), with: lids, lineWidth: 4)
        }

        context.drawLayer { body in
            if s.blur > 0.01 { body.addFilter(.blur(radius: s.blur * unit)) }

            // The iris, clipped to the opening, keyhole punched out.
            body.drawLayer { iris in
                iris.clip(to: Path(GlanceGeometry.opening(s.lid)))
                let ball = GlanceGeometry.eyeball(s)
                let r = GlanceGeometry.irisRadius
                iris.fill(
                    Path(ellipseIn: CGRect(x: 100 - r, y: 100 - r, width: r * 2, height: r * 2)).applying(ball),
                    with: .color(ProsperColor.ink)
                )
                iris.blendMode = .destinationOut
                iris.fill(Path(ellipseIn: GlanceGeometry.pupil(key: s.key)).applying(ball), with: .color(.black))
                if s.key > 0.001 {
                    iris.fill(Path(GlanceGeometry.stem(key: s.key)).applying(ball), with: .color(.black))
                }
            }

            body.drawLayer { lid in
                if s.draw < 1 {
                    lid.clip(to: Path(roundedRect: GlanceGeometry.reveal(s.draw), cornerRadius: 8))
                }
                lid.fill(Path(GlanceGeometry.lowerLid), with: lids)
                lid.fill(Path(GlanceGeometry.upperLid(s.lid)), with: lids)
            }
        }
    }
}

/// The launch reveal: the mark plays its five beats once, then the name
/// unmasks beneath it. Never loops. Under Reduce Motion it is a short fade to
/// the resting mark. VoiceOver hears the name once, as a heading.
/// `replayable` lets a tap play it again (Settings, DS-11).
struct GlanceReveal: View {
    var markSize: CGFloat = 132
    var replayable = false
    /// False shows the resting mark until the first tap (Settings).
    var autoplay = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var finished = false
    @State private var shown = false
    @State private var run = 0

    var body: some View {
        Group {
            if reduceMotion {
                lockup(.rest)
                    .opacity(shown ? 1 : 0)
                    .onAppear { withAnimation(.easeOut(duration: 0.3)) { shown = true } }
            } else if finished || (!autoplay && run == 0) {
                // Static once played, so nothing keeps redrawing (it never loops).
                lockup(.rest)
            } else if let start {
                TimelineView(.animation) { timeline in
                    lockup(GlanceTimeline.state(at: timeline.date.timeIntervalSince(start)))
                }
            } else {
                lockup(GlanceTimeline.state(at: 0))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if replayable && !reduceMotion && (finished || (!autoplay && run == 0)) { run += 1 } }
        .task(id: run) {
            guard !reduceMotion, autoplay || run > 0 else { return }
            finished = false
            start = Date()
            try? await Task.sleep(for: .seconds(GlanceTimeline.duration))
            if !Task.isCancelled { finished = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stolen Glance")
        .accessibilityAddTraits(replayable ? .isButton : .isHeader)
        .accessibilityHint(replayable && !reduceMotion ? "Plays the logo animation again." : "")
        .accessibilityAction { if replayable && !reduceMotion { run += 1 } }
    }

    private func lockup(_ s: GlanceState) -> some View {
        VStack(spacing: 14) {
            GlanceMark(state: s)
                .frame(width: markSize, height: markSize)
            Text("Stolen Glance")
                .scaledFont(34, weight: .semibold)
                .tracking(-0.8)
                .foregroundStyle(ProsperColor.ink)
                // The name unmasks left to right, settling in from a blur.
                .mask(alignment: .leading) {
                    GeometryReader { proxy in
                        Rectangle().frame(width: proxy.size.width * s.word)
                    }
                }
                .offset(x: -10 * (1 - s.word))
                .blur(radius: 4 * (1 - s.word))
                .opacity(Double(s.word))
        }
    }
}

#Preview("Reveal") {
    GlanceReveal()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProsperColor.background)
}
