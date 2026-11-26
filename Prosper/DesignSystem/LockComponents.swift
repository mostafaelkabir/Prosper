import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The taps in the hand that go with a lock. UIKit's generators on the
/// iPhone; on the Mac the Force Touch trackpad, which has three kinds and no
/// intensity, so the soft ticks of a hold become alignment taps there.
enum LockHaptic {
    case tick(Double), release, success, thud

    func play() {
        #if canImport(UIKit)
        switch self {
        case .tick(let intensity): UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
        case .release: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .thud: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        #else
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch self {
        case .tick: pattern = .alignment
        case .release: pattern = .generic
        case .success, .thud: pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        #endif
    }
}

/// Circular countdown for an active block. `progress` is the fraction of time
/// remaining (1 → full ring, 0 → empty).
struct CountdownRing: View {
    let progress: Double
    let centerText: String
    var caption: String? = "remaining"
    var size: CGFloat = 196
    var lineWidth: CGFloat = 5
    /// The final stretch (e.g. last 60s): the ring goes ember to signal urgency
    /// without an idle animation that would encourage watching the timer.
    var emphasize: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(ProsperColor.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(emphasize ? ProsperColor.ember : ProsperColor.slate,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(centerText)
                    .font(ProsperFont.hero(size * 0.17))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                if let caption, size >= 120 {
                    Text(caption).labelCaps()
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Press-and-hold control that commits an irreversible action. The fill runs
/// left-to-right over `duration`; releasing early cancels. Haptics quicken and
/// strengthen through the hold and confirm on completion (suppressed under
/// Reduce Motion, along with the press and glow; the fill itself stays, since
/// it is the affordance).
///
/// The lit leading edge and the settle into a checkmark follow Opal's hold to
/// commit (60fps.design/shots/opal-hold-to-commit-button-interaction): the
/// hold is the friction, so it should feel like something is being sealed.
///
/// VoiceOver, Voice Control and Switch Control cannot hold, so for them it is
/// a button whose hint states the consequence; activating it commits (UX-27).
/// The height grows with Dynamic Type instead of clipping the label.
struct HoldToLock: View {
    var title: String = "Hold to lock"
    /// Shown with a checkmark for the moment after the hold completes.
    var doneTitle: String = "Locked"
    var symbol: String = "lock.fill"
    var duration: Double = 2.0
    /// The fill. Violet for a commitment; ember for the rare hold that loosens.
    var tint: Color = ProsperColor.accent
    var onTint: Color = ProsperColor.onAccent
    /// False for a hold that should not lead the screen: it rests as a plain
    /// tile and only takes colour while it is held.
    var prominent = true
    /// What happens, spoken after the title. Say it plainly: it cannot be undone.
    var accessibilityHint: String = "Starts the lock now. Nothing can end it early."
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var progress: Double = 0
    @State private var holding = false
    @State private var done = false
    @State private var beat = 0
    @State private var timer: Timer?

    /// Where in the hold each tick lands: closer together toward the end.
    private static let beats: [Double] = [0.1, 0.28, 0.44, 0.58, 0.7, 0.8, 0.88, 0.95]

    private var label: String {
        if done { return doneTitle }
        return progress > 0 ? "Keep holding…" : title
    }

    var body: some View {
        ZStack {
            // At rest it is the darkest thing on the screen, unlike every
            // tap button: this one asks for more than a tap.
            face(
                text: prominent ? ProsperColor.background : ProsperColor.ink,
                icon: prominent ? ProsperColor.background : tint
            )
            .background(prominent ? ProsperColor.ink : ProsperColor.surface2)
            // The same face in the fill's colours, shown only where the fill
            // has reached, so the words stay readable on both halves.
            face(text: onTint, icon: onTint)
                .background(
                    LinearGradient(
                        colors: [tint.opacity(0.82), tint],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * progress)
                    }
                }
                .overlay(alignment: .leading) {
                    // The lit edge of the fill.
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 8)
                            .blur(radius: 7)
                            .offset(x: geo.size.width * progress - 4)
                            .opacity(progress > 0 && progress < 1 && !reduceMotion ? 1 : 0)
                    }
                    .allowsHitTesting(false)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(
            color: tint.opacity((prominent ? 0.2 : 0) + (reduceMotion ? 0 : 0.4 * progress)),
            radius: 6 + 14 * progress, y: 3
        )
        .scaleEffect(holding && !reduceMotion ? 0.975 : 1)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Treat a clear vertical drag as a scroll, not a hold.
                    if abs(value.translation.height) > 12 { cancel(); return }
                    if !holding { begin() }
                }
                .onEnded { _ in cancel() }
        )
        .animation(.easeOut(duration: 0.2), value: progress == 0)
        .animation(.spring(duration: 0.25), value: holding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled, progress < 1 else { return }
            progress = 1
            complete()
        }
    }

    private func face(text: Color, icon: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark" : symbol)
                .foregroundStyle(icon)
                .contentTransition(.symbolEffect(.replace))
            Text(label)
                .foregroundStyle(text)
                .contentTransition(.opacity)
        }
        .font(.headline)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56)
        .animation(.easeOut(duration: 0.18), value: label)
    }

    private func begin() {
        guard isEnabled, !done else { return }
        holding = true
        beat = 0
        // Measured against the clock, not counted in ticks: a busy main
        // thread fires the timer late, and a 2 second hold must stay 2 seconds.
        let began = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            // scheduledTimer fires on the main run loop, so this really is the main
            // actor; assert it to satisfy Swift 6 concurrency (QA-5).
            MainActor.assumeIsolated {
                progress = min(1, Date().timeIntervalSince(began) / duration)
                if beat < Self.beats.count, progress >= Self.beats[beat] {
                    beat += 1
                    if !reduceMotion {
                        LockHaptic.tick(0.35 + 0.65 * progress).play()
                    }
                }
                if progress >= 1 { complete() }
            }
        }
    }

    private func complete() {
        timer?.invalidate(); timer = nil
        done = true
        if !reduceMotion { LockHaptic.success.play() }
        onComplete()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            progress = 0
            holding = false
            done = false
        }
    }

    private func cancel() {
        guard holding, progress < 1 else { return }
        timer?.invalidate(); timer = nil
        holding = false
        if !reduceMotion { LockHaptic.release.play() }
        progress = 0
    }
}

/// The moment a lock takes hold, shown over the sheet that started it.
///
/// A violet glow draws in to the middle of the screen. Inside a ring, the
/// Stolen Glance eye glances aside, then its lid snaps shut with a thud in the
/// hand as the ring closes and a ripple leaves, and it opens again on a
/// keyhole, gaze lowered (`GlanceTimeline.seal`, DS-11). Then it says until
/// when, and a word of encouragement. About a second and a half, once, and
/// the sheet closes on the countdown. The drawing-in follows Peace Out's start
/// (60fps.design/shots/peace-out-timer-screen-animation): the screen gathers
/// to a point, which is what the lock does to the phone.
///
/// Under Reduce Motion it is a plain fade to the closed lock and the words.
struct LockSeal: View {
    let until: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gathered = false
    @State private var closed = false
    @State private var rippled = false
    @State private var worded = false
    @State private var eyeStart: Date?
    @State private var eyeDone = false

    private var untilText: String {
        Calendar.current.isDateInToday(until)
            ? until.formatted(date: .omitted, time: .shortened)
            : until.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ZStack {
            ProsperColor.background.ignoresSafeArea()
            RadialGradient(
                colors: [ProsperColor.accent.opacity(0.5), ProsperColor.accent.opacity(0)],
                center: .center, startRadius: 0, endRadius: 300
            )
            .scaleEffect(gathered || reduceMotion ? 0.75 : 1.9)
            .opacity(gathered ? 1 : 0)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    if closed && !reduceMotion {
                        Circle()
                            .stroke(ProsperColor.accent, lineWidth: 2)
                            .scaleEffect(rippled ? 2 : 1)
                            .opacity(rippled ? 0 : 0.7)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.8)) { rippled = true }
                            }
                    }
                    Circle().stroke(ProsperColor.line, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: closed ? 1 : 0)
                        .stroke(ProsperColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    eye
                        .frame(width: 92, height: 92)
                        .scaleEffect(closed || reduceMotion ? 1 : 1.12)
                }
                .frame(width: 132, height: 132)

                VStack(spacing: 6) {
                    Text("Locked")
                        .font(ProsperFont.hero(34))
                        .foregroundStyle(ProsperColor.ink)
                    Text("until \(untilText)")
                        .scaledFont(17, weight: .medium)
                        .foregroundStyle(ProsperColor.ink2)
                }
                .modifier(Rise(shown: worded, order: 0, reduceMotion: reduceMotion))

                Text("Good call. Nothing can end it early.")
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink)
                    .multilineTextAlignment(.center)
                    .modifier(Rise(shown: worded, order: 2, reduceMotion: reduceMotion))
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked until \(untilText). Good call. Nothing can end it early.")
        .onAppear(perform: play)
    }

    /// The eye's seal beat, then the resting mark so nothing keeps redrawing.
    @ViewBuilder private var eye: some View {
        if reduceMotion || eyeDone {
            GlanceMark()
        } else if let eyeStart {
            TimelineView(.animation) { timeline in
                GlanceMark(state: GlanceTimeline.seal(at: timeline.date.timeIntervalSince(eyeStart)))
            }
        } else {
            GlanceMark(state: GlanceTimeline.seal(at: 0))
        }
    }

    private func play() {
        AccessibilityNotification.Announcement("Locked until \(untilText)").post()
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) {
                gathered = true
                closed = true
                worded = true
            }
            return
        }
        withAnimation(.easeIn(duration: 0.45)) { gathered = true }
        eyeStart = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + GlanceTimeline.sealDuration) { eyeDone = true }
        // The lid lands with the ring and the thud.
        DispatchQueue.main.asyncAfter(deadline: .now() + GlanceTimeline.sealShut) {
            withAnimation(.spring(duration: 0.5, bounce: 0.45)) { closed = true }
            LockHaptic.thud.play()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { worded = true }
    }
}

/// A screen that centres its content (with `Spacer`s) when it fits, and
/// scrolls when large text makes it taller than the screen, instead of
/// squeezing sentences into "…" (UX-27).
struct FitOrScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content.frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
