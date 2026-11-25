import SwiftUI

// Controls for the things worth making easy: starting a lock and setting a
// schedule (UX-30). Motion references are from 60fps.design; the content and
// look are our own.

// MARK: - Card surface

extension View {
    /// The Aurora card: surface fill, 18pt continuous corners, hairline border.
    func auroraCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ProsperColor.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

/// The full-width violet action. `quiet` is the tinted second choice.
struct AuroraButtonStyle: ButtonStyle {
    var quiet = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(16, weight: .semibold)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(quiet ? ProsperColor.accent : ProsperColor.onAccent)
            .background(quiet ? ProsperColor.accent.opacity(0.14) : ProsperColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Fades and lifts a view in, a beat after the one before it, the first time
/// it is shown (the staggered reveal of Bevel's onboarding lists,
/// 60fps.design/shots/bevel-onboarding). Does nothing under Reduce Motion.
struct Rise: ViewModifier {
    let shown: Bool
    var order = 0
    var reduceMotion = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.07 * Double(order)), value: shown)
    }
}

/// A ring of sparks thrown out once from a point, for the moment something
/// is won. Fires each time `trigger` changes; draws nothing at rest and
/// nothing at all under Reduce Motion.
struct SparkBurst: View {
    let trigger: Int
    var count = 10
    var radius: CGFloat = 26
    var color: Color = ProsperColor.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            // Rest, thrown, gone. The animator runs the three once per trigger.
            PhaseAnimator([0, 1, 2], trigger: trigger) { phase in
                ZStack {
                    ForEach(0..<count, id: \.self) { index in
                        let angle = Double(index) / Double(count) * 2 * .pi
                        let reach = phase == 0 ? 6 : (phase == 1 ? radius * 0.7 : radius)
                        Capsule()
                            .fill(color)
                            .frame(width: 3, height: index.isMultiple(of: 2) ? 9 : 5)
                            .rotationEffect(.radians(angle + .pi / 2))
                            .offset(x: cos(angle) * reach, y: sin(angle) * reach)
                    }
                }
                .opacity(phase == 1 ? 1 : 0)
            } animation: { phase in
                switch phase {
                case 1: .easeOut(duration: 0.22)
                case 2: .easeOut(duration: 0.4)
                default: nil
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Lock length

/// How long a lock runs, in the five-minute steps the dial moves in.
/// Plain arithmetic, so it belongs to no actor and can be tested anywhere.
nonisolated enum LockLength {
    /// Minutes between two marks on the dial.
    static let step = 5

    static func minutes(_ duration: TimeInterval) -> Int {
        Int((duration / 60).rounded())
    }

    /// The nearest mark, kept inside the allowed range.
    static func snapped(_ minutes: Int, min lower: Int, max upper: Int) -> Int {
        let nearest = Int((Double(minutes) / Double(step)).rounded()) * step
        // The top of the range may not sit on a mark (23h 55m does, a cap of
        // 4h does); the bounds win over the grid.
        return Swift.min(Swift.max(nearest, lower), upper)
    }

    /// Every mark on the dial, shortest first.
    static func marks(min lower: Int, max upper: Int) -> [Int] {
        guard lower <= upper else { return [] }
        return Array(stride(from: lower, through: upper, by: step))
    }

    /// "45m", "2h", "1h 30m".
    static func text(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours)h \(rest)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(rest)m"
    }

    /// The same length said out loud: "1 hour 30 minutes".
    static func spoken(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if rest > 0 || hours == 0 { parts.append(rest == 1 ? "1 minute" : "\(rest) minutes") }
        return parts.joined(separator: " ")
    }

    /// When a lock of this length would end, with the day when that is not
    /// today, so "until 2:15" can never quietly mean tomorrow.
    static func endText(after duration: TimeInterval, from now: Date = .now, calendar: Calendar = .current) -> String {
        let end = now.addingTimeInterval(duration)
        return calendar.isDate(end, inSameDayAs: now)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
    }
}

/// The length of a lock as one big number over a ruler you drag.
///
/// The old picker was a row of grey capsules and two wheels, below the fold.
/// Here the number, the time it ends and the control are one thing: drag the
/// ruler and both update on every mark, with a tick in the hand. The feel
/// follows CRED's amount ruler (60fps.design/shots/cred-custom-amount-slider-interaction).
///
/// VoiceOver and Switch Control get one adjustable element that moves in
/// 15-minute steps; the shortcuts under the ruler are ordinary buttons.
struct DurationDial: View {
    @Binding var duration: TimeInterval
    var minimum: TimeInterval = 15 * 60
    var maximum: TimeInterval
    /// One-tap lengths under the ruler; any longer than `maximum` are left out.
    var shortcuts: [TimeInterval] = [1800, 3600, 7200, 14400, 28800]

    /// The mark under the needle, in minutes. Drives the scroll position.
    @State private var position: Int?
    /// False until the ruler has been laid out and brought to the bound
    /// length. Before that the scroll view reports its first mark, which must
    /// not be taken for a choice.
    @State private var settled = false

    private static let tickWidth: CGFloat = 12

    private var lower: Int { LockLength.minutes(minimum) }
    private var upper: Int { max(lower, LockLength.minutes(maximum)) }
    private var minutes: Int { LockLength.snapped(LockLength.minutes(duration), min: lower, max: upper) }

    init(
        duration: Binding<TimeInterval>,
        minimum: TimeInterval = 15 * 60,
        maximum: TimeInterval,
        shortcuts: [TimeInterval] = [1800, 3600, 7200, 14400, 28800]
    ) {
        _duration = duration
        self.minimum = minimum
        self.maximum = maximum
        self.shortcuts = shortcuts
    }

    var body: some View {
        VStack(spacing: 14) {
            readout
            ruler
            shortcutRow
        }
        .onAppear {
            // A scroll position set before the first layout is not honoured
            // and the ruler opens on its shortest mark, so it is set one turn
            // of the run loop later, once there is something to scroll.
            DispatchQueue.main.async {
                position = minutes
                settled = true
            }
        }
        .onChange(of: position) { _, mark in
            guard settled, let mark, mark != LockLength.minutes(duration) else { return }
            duration = TimeInterval(mark * 60)
        }
        .onChange(of: duration) { _, _ in sync(animated: true) }
        .onChange(of: maximum) { _, _ in sync(animated: false) }
        .sensoryFeedback(.selection, trigger: settled ? position : nil)
    }

    /// Brings the ruler to the bound length, which a shortcut, a cap or the
    /// screen that owns it may have changed.
    private func sync(animated: Bool) {
        let mark = minutes
        if TimeInterval(mark * 60) != duration { duration = TimeInterval(mark * 60) }
        guard settled, position != mark else { return }
        if animated {
            withAnimation(.snappy(duration: 0.3)) { position = mark }
        } else {
            position = mark
        }
    }

    // MARK: Readout

    private var readout: some View {
        // The end time moves with the clock, so it is re-read while the sheet
        // sits open.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            VStack(spacing: 2) {
                Text(LockLength.text(minutes: minutes))
                    // The one number that owns the screen: fixed, like every hero.
                    .font(ProsperFont.hero(52))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .animation(.snappy(duration: 0.2), value: minutes)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("until \(LockLength.endText(after: TimeInterval(minutes * 60), from: context.date))")
                    .scaledFont(15, weight: .medium)
                    .foregroundStyle(ProsperColor.ink2)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: minutes)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true) // spoken by the ruler
        }
    }

    // MARK: Ruler

    private var ruler: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(LockLength.marks(min: lower, max: upper), id: \.self) { mark in
                        tick(mark)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $position, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            // Room either side so the first and last mark can reach the needle.
            .safeAreaPadding(.horizontal, max(0, (geo.size.width - Self.tickWidth) / 2))
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .overlay(alignment: .top) { needle }
        }
        .frame(height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Length")
        .accessibilityValue("\(LockLength.spoken(minutes: minutes)), until \(LockLength.endText(after: TimeInterval(minutes * 60)))")
        .accessibilityAdjustableAction { direction in
            let change = direction == .increment ? 15 : -15
            duration = TimeInterval(LockLength.snapped(minutes + change, min: lower, max: upper) * 60)
        }
    }

    private func tick(_ mark: Int) -> some View {
        let isHour = mark % 60 == 0
        let isHalf = mark % 30 == 0
        let passed = mark <= minutes
        return VStack(spacing: 5) {
            Capsule()
                .fill(passed ? ProsperColor.accent : ProsperColor.unclassified.opacity(isHour ? 0.9 : 0.5))
                .frame(width: isHour ? 2.5 : 1.5, height: isHour ? 26 : (isHalf ? 18 : 10))
            if isHour {
                Text("\(mark / 60)h")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(passed ? ProsperColor.accent : ProsperColor.ink2)
                    .fixedSize()
            }
        }
        .frame(width: Self.tickWidth, height: 58, alignment: .top)
    }

    private var needle: some View {
        Capsule()
            .fill(ProsperColor.ink)
            // Just past the hour marks, short of their labels.
            .frame(width: 3, height: 29)
            .shadow(color: ProsperColor.accent.opacity(0.5), radius: 6)
            .allowsHitTesting(false)
    }

    // MARK: Shortcuts

    private var shortcutRow: some View {
        let offered = shortcuts.filter { $0 >= minimum && $0 <= maximum }
        return HStack(spacing: 8) {
            ForEach(offered, id: \.self) { length in
                let mark = LockLength.minutes(length)
                let selected = mark == minutes
                Button {
                    duration = length
                } label: {
                    Text(LockLength.text(minutes: mark))
                        .scaledFont(15, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? ProsperColor.onAccent : ProsperColor.ink)
                        .background(selected ? ProsperColor.accent : ProsperColor.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LockLength.spoken(minutes: mark))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: minutes)
    }
}

// MARK: - Day band

/// Where a schedule's hours fall in a day, as fractions from midnight (0) to
/// the next midnight (1). Kept off the view that draws it: a view's code runs
/// on the main actor, and this is arithmetic that tests call from anywhere.
nonisolated enum DaySpan {
    static let minutesPerDay = 24 * 60

    /// The locked stretches. A window that ends at or before its start runs
    /// past midnight and comes back as two pieces: the morning, then the night.
    static func segments(start: Int, end: Int) -> [ClosedRange<Double>] {
        let day = Double(minutesPerDay)
        let s = Double(min(max(start, 0), minutesPerDay)) / day
        let e = Double(min(max(end, 0), minutesPerDay)) / day
        if end > start { return [s...e] }
        var pieces: [ClosedRange<Double>] = []
        if e > 0 { pieces.append(0...e) }
        if s < 1 { pieces.append(s...1) }
        return pieces
    }

    /// Where `date` falls in its day.
    static func fraction(of date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / Double(minutesPerDay)
    }
}

/// A day drawn as one bar, midnight to midnight, with the locked hours filled
/// in. A schedule's two times become something you can see: a bedtime lock
/// reads as a bar that wraps around the night.
///
/// It redraws as the times change, so setting a schedule shows its result
/// while you set it, the way Sudoku's reminder picker updates its lock screen
/// (60fps.design/shots/sudoku-daily-reminder-time-picker-interaction).
struct DayBand: View {
    let startMinute: Int
    let endMinute: Int
    /// Draws a marker at this time of day. Nil leaves it out.
    var now: Date? = nil
    var height: CGFloat = 12
    var showsHours = true

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // A wash of ink, so the track shows on every surface.
                    Capsule().fill(ProsperColor.ink.opacity(0.1))
                    ForEach(Array(DaySpan.segments(start: startMinute, end: endMinute).enumerated()), id: \.offset) { _, piece in
                        // Squared ends: the bar's own capsule rounds midnight,
                        // and a start or end time is an edge, not a blob.
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(ProsperColor.accent)
                            .frame(width: max(4, width * (piece.upperBound - piece.lowerBound)))
                            .offset(x: width * piece.lowerBound)
                    }
                    // Quarter marks, so the bar reads as a day and not a progress bar.
                    ForEach(1..<4, id: \.self) { quarter in
                        Rectangle()
                            .fill(ProsperColor.surface.opacity(0.7))
                            .frame(width: 1)
                            .offset(x: width * Double(quarter) / 4)
                    }
                    if let now {
                        Circle()
                            .fill(ProsperColor.ink)
                            .frame(width: height + 4, height: height + 4)
                            .overlay(Circle().strokeBorder(ProsperColor.surface, lineWidth: 2))
                            .offset(x: width * DaySpan.fraction(of: now) - (height + 4) / 2)
                    }
                }
                .frame(height: height + 4)
                .clipShape(Capsule())
                .animation(.snappy(duration: 0.3), value: startMinute)
                .animation(.snappy(duration: 0.3), value: endMinute)
            }
            .frame(height: height + 4)
            if showsHours {
                HStack(spacing: 0) {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(Self.hourLabel(hour))
                            .scaledFont(10, weight: .medium)
                            .foregroundStyle(ProsperColor.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityHidden(true) // the times are always written out beside it
    }

    private static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}
