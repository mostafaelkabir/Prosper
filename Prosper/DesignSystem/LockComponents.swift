import SwiftUI
import UIKit

/// Circular countdown for an active block. `progress` is the fraction of time
/// remaining (1 → full ring, 0 → empty).
struct CountdownRing: View {
    let progress: Double
    let centerText: String
    var caption: String? = "remaining"
    var size: CGFloat = 196
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .stroke(ProsperColor.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(ProsperColor.slate, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
/// left-to-right over `duration`; releasing early cancels. Haptics tick during
/// the hold and confirm on completion (suppressed under Reduce Motion — the
/// fill itself stays, since it is the affordance).
struct HoldToLock: View {
    var title: String = "Hold to lock"
    var duration: Double = 2.0
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var holding = false
    @State private var lastTick = 0
    @State private var timer: Timer?

    private var label: String {
        if progress >= 1 { return "Locked" }
        return progress > 0 ? "Keep holding…" : title
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ProsperColor.card2)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ProsperColor.slate)
                    .frame(width: geo.size.width * progress)
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text(label)
                }
                .font(.headline)
                .foregroundStyle(progress > 0.55 ? Color.white : ProsperColor.ink)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    }

    private func begin() {
        holding = true
        lastTick = 0
        let step = 0.02
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { _ in
            progress = min(1, progress + step / duration)
            let tick = Int((progress * duration) / 0.5)
            if tick > lastTick {
                lastTick = tick
                if !reduceMotion { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
            if progress >= 1 { complete() }
        }
    }

    private func complete() {
        timer?.invalidate(); timer = nil
        if !reduceMotion { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        onComplete()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            progress = 0
            holding = false
        }
    }

    private func cancel() {
        guard holding, progress < 1 else { return }
        timer?.invalidate(); timer = nil
        holding = false
        if !reduceMotion { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        progress = 0
    }
}
