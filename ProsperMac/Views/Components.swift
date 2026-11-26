import AppKit
import SwiftUI

/// A hold-to-confirm button: the deliberate gesture the iPhone uses before
/// anything that cannot be undone (a lock, the guard). Hold the mouse, or Tab
/// to it and hold Space or Return; VoiceOver activates it directly (UX-27).
///
/// It looks and moves like the iPhone's `HoldToLock` (DS-12): at rest it is
/// the darkest thing on the screen, the violet fill runs left to right with a
/// lit leading edge and a glow that grows with the hold, and it settles on a
/// checkmark. The trackpad taps through the hold where it can. Under Reduce
/// Motion the press, glow and edge drop out; the fill stays, it is the cue.
struct HoldToConfirmButton: View {
    let title: String
    var systemImage: String = "lock.fill"
    var doneTitle: String = "Locked"
    var duration: Double = 1.5
    var enabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var holding = false
    @State private var done = false
    @State private var beat = 0
    @State private var timer: Timer?
    /// The mouse or key is down for the current press. A press that already
    /// finished (or slid off) does not start again until it is released.
    @State private var mouseDown = false
    @State private var keyDown = false
    @State private var holdStart = Date()
    /// Set when a press is let go before the bar fills, so a click or a short
    /// press says what to do instead of doing nothing.
    @State private var tooShort = false

    /// Where in the hold each tick lands: closer together toward the end.
    private static let beats: [Double] = [0.1, 0.28, 0.44, 0.58, 0.7, 0.8, 0.88, 0.95]

    private var label: String {
        if done { return doneTitle }
        if holding { return "Keep holding…" }
        if tooShort { return "Press and hold until the bar fills (\(Self.seconds(duration)))" }
        return title
    }

    var body: some View {
        ZStack {
            face(text: enabled ? ProsperColor.background : ProsperColor.ink2,
                 icon: enabled ? ProsperColor.background : ProsperColor.ink2)
                .background(enabled ? ProsperColor.ink : ProsperColor.surface2)
            // The same face in the fill's colours, shown only where the fill
            // has reached, so the words stay readable on both halves.
            face(text: ProsperColor.onAccent, icon: ProsperColor.onAccent)
                .background(LinearGradient(colors: [ProsperColor.accent.opacity(0.82), ProsperColor.accent],
                                           startPoint: .leading, endPoint: .trailing))
                .mask(alignment: .leading) {
                    GeometryReader { geo in Rectangle().frame(width: geo.size.width * (done ? 1 : progress)) }
                }
                .overlay(alignment: .leading) {
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: ProsperColor.accent.opacity((enabled ? 0.18 : 0) + (reduceMotion ? 0 : 0.4 * progress)),
                radius: 6 + 14 * progress, y: 3)
        .scaleEffect(holding && !reduceMotion ? 0.985 : 1)
        .animation(.spring(duration: 0.25), value: holding)
        .harnessFrame("hold:\(title)")
        .contentShape(Rectangle())
        // Mouse down starts the hold, mouse up before the end lets it go and
        // the timer finishes it. A zero-distance drag reports both edges
        // reliably on macOS; onLongPressGesture next to a click-focusable view
        // never completed, so the lock button did nothing.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard enabled else { return }
                    if !mouseDown {
                        mouseDown = true
                        begin()
                    } else if holding, max(abs(value.translation.width), abs(value.translation.height)) > 40 {
                        cancel()
                    }
                }
                .onEnded { _ in
                    mouseDown = false
                    if holding { cancel() }
                }
        )
        // Focus comes from keyboard navigation only, so a click goes to the
        // hold gesture instead of moving focus.
        .focusable(enabled, interactions: .activate)
        .onKeyPress(keys: [.space, .return], phases: [.down, .up]) { press in
            guard enabled else { return .ignored }
            if press.phase == .down {
                if !keyDown { keyDown = true; begin() }
            } else {
                keyDown = false
                if holding { cancel() }
            }
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint(enabled ? "Hold to confirm. It cannot be undone." : "Choose something first.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled { action() } }
    }

    private func begin() {
        guard !done else { return }
        holdStart = Date()
        tooShort = false
        holding = true
        progress = 0
        beat = 0
        let start = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1 / 60, repeats: true) { t in
            let p = min(1, Date().timeIntervalSince(start) / duration)
            Task { @MainActor in
                guard holding else { return }
                progress = p
                if beat < Self.beats.count, p >= Self.beats[beat] {
                    beat += 1
                    if !reduceMotion { LockHaptic.tick(p).play() }
                }
                if p >= 1 { finish() }
            }
            if p >= 1 { t.invalidate() }
        }
        // Common modes keep it ticking while the mouse is held down.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func cancel() {
        timer?.invalidate()
        if holding {
            tooShort = true
            let shownAt = Date()
            holdStart = shownAt
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if holdStart == shownAt, !holding { tooShort = false }
            }
        }
        holding = false
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }

    private func finish() {
        guard enabled else { return }
        tooShort = false
        timer?.invalidate()
        holding = false
        done = true
        if !reduceMotion { LockHaptic.success.play() }
        action()
        // A beat on the checkmark, then back to rest.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            done = false
            progress = 0
        }
    }

    private func face(text: Color, icon: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark" : systemImage)
                .foregroundStyle(icon)
                .contentTransition(.symbolEffect(.replace))
            Text(label)
                .foregroundStyle(text)
                .contentTransition(.opacity)
        }
        .scaledFont(15, weight: .semibold)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .animation(.easeOut(duration: 0.18), value: label)
    }
}

extension HoldToConfirmButton {
    static func seconds(_ duration: Double) -> String {
        duration == duration.rounded() ? "\(Int(duration)) s" : String(format: "%.1f s", duration)
    }
}

/// An app icon by bundle ID, or a platform's brand tile, or a site's initial.
struct RowIcon: View {
    let kind: UsageRow.Kind
    var size: CGFloat = 26

    var body: some View {
        switch kind {
        case .app(let bundleID):
            Image(nsImage: InstalledApps.named(bundleID).icon)
                .resizable()
                .frame(width: size, height: size)
        case .platform(let id):
            if let platform = PlatformCatalog.platform(id: id) {
                BrandTile(platform: platform, size: size)
            }
        case .site(let domain):
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(ProsperColor.surface2)
                Text(String(domain.prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(ProsperColor.ink2)
            }
            .frame(width: size, height: size)
        }
    }
}

/// A platform's brand tile: its colour and its own mark from
/// `BrandLogos.xcassets` (the same bundled Simple Icons marks as the iPhone,
/// never downloaded), with a hairline so near-black brands stay visible on
/// the dark theme. A platform with no bundled mark keeps its SF Symbol.
struct BrandTile: View {
    let platform: Platform
    var size: CGFloat = 26

    private var rgb: (r: Double, g: Double, b: Double) {
        (Double((platform.tintHex >> 16) & 0xFF) / 255, Double((platform.tintHex >> 8) & 0xFF) / 255, Double(platform.tintHex & 0xFF) / 255)
    }

    /// Black or white, whichever stays readable on the brand colour.
    private var onTint: Color {
        0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b > 0.6 ? .black : .white
    }

    private var logoName: String? {
        let name = "brand-" + platform.id
        return NSImage(named: name) != nil ? name : nil
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
            .overlay(mark.foregroundStyle(onTint))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(ProsperColor.line.opacity(0.6), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
    }

    @ViewBuilder private var mark: some View {
        if let logoName {
            Image(logoName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.58, height: size * 0.58)
        } else {
            Image(systemName: platform.symbol)
                .font(.system(size: size * 0.48, weight: .bold))
        }
    }
}

/// A list row of usage with a class dot and a menu to relabel it.
struct UsageRowView: View {
    let row: UsageRow
    let maxSeconds: Double
    /// Its place in the list, so the bars grow in one after another.
    var order = 0
    var onClass: ((TimeClassKind?) -> Void)?

    @State private var grown = false
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(kind: row.kind)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.name).font(.system(size: 13, weight: .medium)).foregroundStyle(ProsperColor.ink).lineLimit(1)
                    Spacer()
                    Text(row.seconds.usageFormatted).font(ProsperFont.dataRow).foregroundStyle(ProsperColor.ink)
                }
                GeometryReader { geo in
                    Capsule().fill(row.timeClass.auroraClass.color)
                        .frame(width: max(3, geo.size.width * (maxSeconds > 0 ? row.seconds / maxSeconds : 0)), height: 4)
                        .growIn(grown || snapshotMode, delay: 0.03 * Double(min(order, 10)))
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 4)
        .onFirstAppear($grown)
        .contentShape(Rectangle())
        .contextMenu {
            if let onClass {
                Text("Label \(row.name)")
                Button("Productive") { onClass(.productive) }
                Button("Distracting") { onClass(.distracting) }
                Button("Intentional rest") { onClass(.rest) }
                Button("Clear label") { onClass(nil) }
            }
        }
        .help("Right-click to label")
    }
}

/// `HeroNumber` for a total that counts up from zero the first time it shows
/// (GrowPal stats, `ChartMotion.count`). Snapshots draw the final value.
struct CountingHero: View {
    let seconds: Double
    var unit: String? = nil
    var size: CGFloat = 48
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if snapshotMode {
                    Text(seconds.usageFormatted).monospacedDigit()
                } else {
                    CountUp(target: seconds, format: { $0.countingFormatted })
                }
            }
            .font(ProsperFont.hero(size))
            .foregroundStyle(ProsperColor.ink)
            if let unit {
                Text(unit).font(.title3.weight(.semibold)).foregroundStyle(ProsperColor.ink2)
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(ProsperColor.ink)
            Text(label).font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
            if let footnote {
                Text(footnote).font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension UsageSummary {
    var balance: TimeBalance {
        TimeBalance(productive: productiveSeconds, distracting: distractingSeconds, rest: restSeconds, unclassified: unclassifiedSeconds)
    }
}

/// Screen background and padding shared by every tab.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: 18) { content }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        if snapshotMode {
            stack.background(ProsperColor.background)
        } else {
            ScrollView { stack }.background(ProsperColor.background)
        }
    }
}

private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering PNG snapshots (Debug only): no scroll views, which ImageRenderer cannot draw.
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}
