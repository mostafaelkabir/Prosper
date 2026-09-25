import SwiftUI

/// Renders the ranked insight cards produced by `InsightEngine`. Lives in the
/// report extension because the cards are built from raw usage there. When the
/// engine has nothing solid to say it shows an honest "still learning" line
/// rather than inventing an insight (DS-8).
struct InsightsReportView: View {
    let cards: [InsightCard]
    /// How many to show — the Today spotlight passes a small number; the full
    /// Insights list passes them all.
    var limit: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if cards.isEmpty {
                emptyState
            } else {
                ForEach(cards.prefix(limit)) { card in
                    InsightCardView(card: card)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The host reserves a fixed height (DeviceActivityReport does not size
        // itself, QA-7), and the serif headline scales with Dynamic Type — at
        // accessibility sizes it ran out of the frame and was clipped. Capping
        // here keeps a worst-case card inside the reserved height (QA-9).
        .dynamicTypeSize(...Self.maxTypeSize)
    }

    /// The largest text size the card is laid out for; the Today host's
    /// reserved height is sized against this.
    static let maxTypeSize = DynamicTypeSize.xLarge

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still learning your day").labelCaps()
            Text("Insights appear once StolenEyes has enough of today's usage to say something true.")
                .font(.system(size: 13))
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One insight, as a card: brand mark, serif headline, plain evidence.
struct InsightCardView: View {
    let card: InsightCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ProsperColor.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.headline)
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.evidence)
                    .font(.system(size: 12))
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProsperColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
