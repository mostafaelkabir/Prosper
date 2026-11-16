import AppKit
import SwiftUI

/// A hold-to-confirm button: the deliberate gesture the iPhone uses before
/// anything that cannot be undone (a lock, the guard). Hold the mouse, or Tab
/// to it and hold Space or Return; VoiceOver activates it directly (UX-27).
struct HoldToConfirmButton: View {
    let title: String
    var systemImage: String = "lock.fill"
    var duration: Double = 1.5
    var enabled: Bool = true
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var holding = false
    @State private var timer: Timer?
    /// The mouse or key is down for the current press. A press that already
    /// finished (or slid off) does not start again until it is released.
    @State private var mouseDown = false
    @State private var keyDown = false
    @State private var holdStart = Date()
    /// Set when a press is let go before the bar fills, so a click or a short
    /// press says what to do instead of doing nothing.
    @State private var tooShort = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(enabled ? ProsperColor.accent.opacity(0.35) : ProsperColor.surface2)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ProsperColor.accent)
                    .frame(width: geo.size.width * progress)
            }
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(holding ? "Keep holding…" : tooShort ? "Press and hold until the bar fills (\(Self.seconds(duration)))" : title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(enabled ? ProsperColor.onAccent : ProsperColor.ink2)
        }
        .frame(height: 46)
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
        holdStart = Date()
        tooShort = false
        holding = true
        progress = 0
        let start = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1 / 60, repeats: true) { t in
            let p = min(1, Date().timeIntervalSince(start) / duration)
            Task { @MainActor in
                guard holding else { return }
                progress = p
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
        progress = 0
        action()
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

struct BrandTile: View {
    let platform: Platform
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(red: Double((platform.tintHex >> 16) & 0xFF) / 255, green: Double((platform.tintHex >> 8) & 0xFF) / 255, blue: Double(platform.tintHex & 0xFF) / 255))
            Image(systemName: platform.symbol)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(platform.tintHex == 0xFFFC00 ? .black : .white)
        }
        .frame(width: size, height: size)
    }
}

/// A list row of usage with a class dot and a menu to relabel it.
struct UsageRowView: View {
    let row: UsageRow
    let maxSeconds: Double
    var onClass: ((TimeClassKind?) -> Void)?

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
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 4)
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
