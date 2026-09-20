import SwiftUI

// MARK: - Time classes & balance

/// The four user-controlled time classes (UX-9). Colours are strict and shared.
enum TimeClass: CaseIterable, Hashable {
    case productive, distracting, rest, unclassified

    var label: String {
        switch self {
        case .productive: return "Productive"
        case .distracting: return "Distracting"
        case .rest: return "Intentional rest"
        case .unclassified: return "Unclassified"
        }
    }

    var color: Color {
        switch self {
        case .productive: return ProsperColor.productive
        case .distracting: return ProsperColor.distracting
        case .rest: return ProsperColor.rest
        case .unclassified: return ProsperColor.unclassified
        }
    }
}

/// A tracked-time distribution across the four classes.
struct TimeBalance: Equatable {
    var productive: TimeInterval = 0
    var distracting: TimeInterval = 0
    var rest: TimeInterval = 0
    var unclassified: TimeInterval = 0

    var total: TimeInterval { productive + distracting + rest + unclassified }

    func value(_ c: TimeClass) -> TimeInterval {
        switch c {
        case .productive: return productive
        case .distracting: return distracting
        case .rest: return rest
        case .unclassified: return unclassified
        }
    }

    /// Fraction 0…1 of the total, or 0 when there is no tracked time.
    func fraction(_ c: TimeClass) -> Double {
        total > 0 ? value(c) / total : 0
    }

    /// VoiceOver summary, e.g. "3h 30m tracked: 2h 10m productive, …".
    var accessibleSummary: String {
        guard total > 0 else { return "No tracked time yet." }
        let parts = TimeClass.allCases.map { "\(value($0).usageFormatted) \($0.label.lowercased())" }
        return "\(total.usageFormatted) tracked: " + parts.joined(separator: ", ")
    }
}

// MARK: - Four-segment time ring

/// The approved four-class ring: ~86pt, 7pt segments, total tracked time in the
/// centre. Encodes the distribution, never a single "productivity score".
struct TimeRing: View {
    let balance: TimeBalance
    var size: CGFloat = 86
    var thickness: CGFloat = 7

    private var segments: [(TimeClass, start: Double, end: Double)] {
        var result: [(TimeClass, Double, Double)] = []
        var cursor = 0.0
        for c in TimeClass.allCases {
            let f = balance.fraction(c)
            result.append((c, cursor, cursor + f))
            cursor += f
        }
        return result
    }

    var body: some View {
        ZStack {
            Circle().stroke(ProsperColor.line, lineWidth: thickness)
            if balance.total > 0 {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.start, to: max(seg.start, seg.end))
                        .stroke(seg.0.color, style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: 1) {
                Text(balance.total.usageFormatted)
                    .font(.system(size: size * 0.19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                Text("TRACKED")
                    .font(.system(size: size * 0.11, weight: .medium))
                    .tracking(0.7)
                    .foregroundStyle(ProsperColor.ink2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(balance.accessibleSummary)
    }
}

// MARK: - 2×2 category breakdown

struct CategoryBreakdown: View {
    let balance: TimeBalance
    private let columns = [GridItem(.flexible(), alignment: .leading),
                           GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(TimeClass.allCases, id: \.self) { c in
                HStack(alignment: .top, spacing: 7) {
                    Circle().fill(c.color).frame(width: 7, height: 7).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(balance.value(c).usageFormatted)
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(ProsperColor.ink)
                        Text(c.label)
                            .font(.system(size: 12))
                            .foregroundStyle(ProsperColor.ink2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Hero surface (radial accent, top-right)

struct AuroraHeroCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(ProsperColor.surface)
                    .overlay(alignment: .topTrailing) {
                        RadialGradient(
                            colors: [ProsperColor.accent.opacity(0.18), .clear],
                            center: .topTrailing, startRadius: 0, endRadius: 240
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(ProsperColor.line, lineWidth: 1)
            }
    }
}

// MARK: - Violet segmented control

struct AuroraSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    /// Drives the sliding-pill animation so the selected segment glides instead
    /// of hard-cutting — the tap feels instant even while the report reloads.
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                let selected = opt.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.26)) { selection = opt.value }
                } label: {
                    Text(opt.label)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? ProsperColor.onAccent : ProsperColor.ink2)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(ProsperColor.accent)
                                    .matchedGeometryEffect(id: "segPill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Focus streak strip

struct StreakDay: Identifiable {
    enum State { case done, current, upcoming }
    let id = UUID()
    let label: String
    let state: State
}

struct StreakStrip: View {
    let title: String
    let days: [StreakDay]
    var onGoal: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "flame.fill").foregroundStyle(ProsperColor.accent)
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(ProsperColor.ink)
                }
                Spacer()
                Button("Your goal", action: onGoal)
                    .font(.system(size: 12))
                    .foregroundStyle(ProsperColor.accent)
                    .frame(minHeight: 44)
            }
            HStack(spacing: 7) {
                ForEach(days) { day in
                    VStack(spacing: 5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(cellFill(day.state))
                            Text(day.state == .upcoming ? "·" : "✓")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(cellInk(day.state))
                        }
                        .frame(height: 33)
                        Text(day.label)
                            .font(.system(size: 10))
                            .foregroundStyle(ProsperColor.ink2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func cellFill(_ s: StreakDay.State) -> Color {
        switch s {
        case .done: return ProsperColor.accent.opacity(0.22)
        case .current: return ProsperColor.accent
        case .upcoming: return ProsperColor.surface
        }
    }
    private func cellInk(_ s: StreakDay.State) -> Color {
        switch s {
        case .done: return ProsperColor.accent
        case .current: return ProsperColor.onAccent
        case .upcoming: return ProsperColor.ink2
        }
    }
}

// MARK: - Opportunity card + focus CTA

struct FocusCTA: View {
    var title: String = "Plan a focus block"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 45)
            .foregroundStyle(ProsperColor.onAccent)
            .background(ProsperColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct OpportunityCard: View {
    var eyebrow: String
    var headline: String
    var evidence: String
    var ctaTitle: String = "Plan a focus block"
    var onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow).labelCaps()
            Text(headline)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ProsperColor.ink)
            Text(evidence)
                .font(.system(size: 12))
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 7)
            FocusCTA(title: ctaTitle, action: onPlan)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ProsperColor.line, lineWidth: 1)
        }
    }
}

// MARK: - Milestone row

struct MilestoneRow: View {
    let completed: Int
    let target: Int
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "leaf.fill").foregroundStyle(ProsperColor.productive)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(completed) of \(target) focus sessions completed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProsperColor.ink)
                Text(remaining == 0 ? "Milestone reached." : "Your next milestone is \(remaining) session\(remaining == 1 ? "" : "s") away.")
                    .font(.system(size: 12))
                    .foregroundStyle(ProsperColor.ink2)
            }
        }
    }
    private var remaining: Int { max(0, target - completed) }
}
