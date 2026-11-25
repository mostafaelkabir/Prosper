import SwiftUI

/// Where the hours went, one card per label (UX-29). Rendered in the report
/// extension, which is the only place iOS shows per-app time; the app hosts it
/// above its label buttons.
struct DayLedgerView: View {
    let ledger: DayLedger

    /// The biggest row anywhere, so bars compare across the cards.
    private var peak: TimeInterval {
        ledger.groups.flatMap(\.rows).map(\.duration).max() ?? 1
    }

    var body: some View {
        ScrollView {
            if ledger.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    ForEach(ledger.groups) { group in
                        card(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                // Clears the floating tab bar when Insights hosts this list.
                .padding(.bottom, 96)
            }
        }
    }

    // MARK: - The whole day in one bar

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ledger.balance.total.usageFormatted)
                    .scaledFont(28, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                Text("on this iPhone")
                    .scaledFont(14)
                    .foregroundStyle(ProsperColor.ink2)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(DayLedger.order, id: \.self) { timeClass in
                        let fraction = ledger.balance.fraction(timeClass)
                        if fraction > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(timeClass.color)
                                .frame(width: max(3, (geo.size.width - 6) * fraction))
                        }
                    }
                }
            }
            .frame(height: 12)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - One label

    private func card(_ group: DayLedger.Group) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(group.timeClass.color)
                    .frame(width: 10, height: 10)
                Text(group.timeClass.ledgerTitle)
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(ProsperColor.ink)
                Spacer(minLength: 8)
                Text(group.total.usageFormatted)
                    .scaledFont(17, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(group.timeClass.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if group.timeClass == .unclassified {
                Text(group.rows.isEmpty
                    ? "Time iOS did not tie to a single app or site."
                    : "Nothing here counts as productive or distracting until you label it.")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(group.rows) { item in
                row(item, color: group.timeClass.color)
            }

            if group.hiddenCount > 0 {
                Text("and \(group.hiddenCount) more, \(group.hiddenDuration.usageFormatted) together")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
            }
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

    private func row(_ item: UsageItem, color: Color) -> some View {
        HStack(spacing: 12) {
            UsageIcon(item, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(ProsperColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.duration.usageFormatted)
                        .scaledFont(15, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(ProsperColor.ink)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * item.duration / max(peak, 1)))
                }
                .frame(height: 5)
                .background(Capsule().fill(ProsperColor.surface2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.duration.usageFormatted)")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 40))
                .foregroundStyle(ProsperColor.ink2)
            Text("No usage recorded yet")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
            Text("Your apps and sites appear here as you use your iPhone. Apple updates it every few minutes.")
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

extension TimeClass {
    /// The label as a heading in the ledger and on the label buttons.
    var ledgerTitle: String {
        switch self {
        case .productive: "Productive"
        case .distracting: "Distracting"
        case .rest: "Rest"
        case .unclassified: "Not labelled yet"
        }
    }
}
