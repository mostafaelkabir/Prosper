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
    /// The full list in Insights fills its section and scrolls; Today's
    /// spotlight sits in a height the host reserves.
    var scrolls = false

    /// Enough for every kind the engine ranks, without becoming a feed.
    nonisolated static let listLimit = 12

    @State private var shown = false

    var body: some View {
        if scrolls {
            ScrollView {
                patterns
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    // Clears the floating tab bar, which overlays the report.
                    .padding(.bottom, 96)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            list
                // The host reserves a fixed height (DeviceActivityReport does not size
                // itself, QA-7), and the serif headline scales with Dynamic Type — at
                // accessibility sizes it ran out of the frame and was clipped. Capping
                // here keeps a worst-case card inside the reserved height (QA-9).
                // The scrolling list needs no cap: it has room.
                .dynamicTypeSize(...Self.maxTypeSize)
        }
    }

    /// Today's spotlight: the strongest card, compact, in the height the
    /// host reserves.
    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            if cards.isEmpty {
                emptyState
            } else {
                ForEach(Array(cards.prefix(limit).enumerated()), id: \.element.id) { index, card in
                    InsightCardView(card: card)
                        .riseIn(shown, order: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onFirstAppear($shown)
    }

    /// The Patterns section: the strongest insight as a lead card with its
    /// number, the rest as compact cards under one heading, lifted in one
    /// after another (Alma's reveal, see `ChartMotion.rise`).
    private var patterns: some View {
        let shownCards = Array(cards.prefix(limit))
        return VStack(alignment: .leading, spacing: 14) {
            if let lead = shownCards.first {
                Text("What stands out").labelCaps()
                    .riseIn(shown, order: 0)
                InsightLeadCard(card: lead)
                    .riseIn(shown, order: 1)
                if shownCards.count > 1 {
                    Text("Also this range").labelCaps()
                        .padding(.top, 10)
                        .riseIn(shown, order: 2)
                    ForEach(Array(shownCards.dropFirst().enumerated()), id: \.element.id) { index, card in
                        InsightCardView(card: card)
                            .riseIn(shown, order: 3 + index)
                    }
                }
            } else {
                learningState
                    .riseIn(shown, order: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onFirstAppear($shown)
    }

    /// The Patterns empty state: what is missing, said plainly, with no
    /// invented insight in its place (DS-8).
    private var learningState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .scaledFont(22, weight: .semibold)
                .foregroundStyle(ProsperColor.accent)
                .frame(width: 44, height: 44)
                .background(ProsperColor.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text("Still learning")
                .font(ProsperFont.insight)
                .foregroundStyle(ProsperColor.ink)
            Text("Patterns appear once this range has enough use to say something true. Check back after a few hours with your phone.")
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .auroraCard(padding: 18)
        .accessibilityElement(children: .combine)
    }

    /// The largest text size the card is laid out for; the Today host's
    /// reserved height is sized against this.
    static let maxTypeSize = DynamicTypeSize.xLarge

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Range-neutral: the same view serves Today and the 7-day range (QA-9).
            Text("Still learning").labelCaps()
            Text("Insights appear once Stolen Glance has enough usage in this range to say something true.")
                .scaledFont(13)
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
                .scaledFont(15, weight: .semibold)
                .foregroundStyle(ProsperColor.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.headline)
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.evidence)
                    .scaledFont(12)
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

/// The strongest insight, given room: what kind it is, its one number large
/// (inside a ring that draws itself when the number is a share), then the
/// headline and the evidence.
struct InsightLeadCard: View {
    let card: InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(card.kindTitle, systemImage: card.systemImage)
                .labelStyle(.titleAndIcon)
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(ProsperColor.accent)

            HStack(alignment: .center, spacing: 16) {
                if let figure = card.figure {
                    figureView(figure)
                }
                Text(card.headline)
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Divider().overlay(ProsperColor.line)

            Text(card.evidence)
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .auroraCard(padding: 18)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func figureView(_ figure: String) -> some View {
        if let fraction = card.fraction {
            ZStack {
                ShareRing(fraction: fraction, lineWidth: 7)
                Text(figure)
                    .font(ProsperFont.hero(20))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 76, height: 76)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(figure)
                    .font(ProsperFont.hero(40))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                if let caption = card.figureCaption {
                    Text(caption)
                        .labelCaps()
                }
            }
            .fixedSize()
        }
    }
}
