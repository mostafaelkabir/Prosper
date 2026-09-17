import SwiftUI

/// The Prosper surface: 20pt continuous-radius card on the `card` colour.
struct ProsperCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProsperColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The one big number that owns a screen. Value is SF Rounded tabular; an
/// optional unit sits in ink2, and an optional delta reads sage (good) or ember.
struct HeroNumber: View {
    let value: String
    var unit: String? = nil
    var delta: String? = nil
    var deltaIsGood: Bool = true
    var size: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(ProsperFont.hero(size))
                    .monospacedDigit()
                    .foregroundStyle(ProsperColor.ink)
                if let unit {
                    Text(unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ProsperColor.ink2)
                }
            }
            if let delta {
                Text(delta)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(deltaIsGood ? ProsperColor.sage : ProsperColor.ember)
            }
        }
    }
}

/// A sentence the user actually reads — serif, with an optional footnote metric.
struct InsightSentence: View {
    let text: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(ProsperFont.insight)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink3)
            }
        }
    }
}

/// Icon + label capsule on the `card2` surface. Replaces the old ChipShape.
struct Chip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.caption.weight(.medium))
            .foregroundStyle(ProsperColor.ink2)
            .lineLimit(1)
            .imageScale(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ProsperColor.card2)
            .clipShape(Capsule())
    }
}

/// Two-segment bar: waste (ember) then everything else (slate), 2pt gap.
struct StackedBar: View {
    /// Waste portion (any unit; only the ratio matters).
    let waste: Double
    /// The rest.
    let other: Double
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let total = max(waste + other, 0.0001)
            let wasteWidth = geo.size.width * (waste / total)
            HStack(spacing: 2) {
                Capsule()
                    .fill(ProsperColor.ember)
                    .frame(width: max(waste > 0 ? 4 : 0, wasteWidth))
                Capsule()
                    .fill(ProsperColor.slate)
            }
        }
        .frame(height: height)
    }
}

/// Text tabs with an underline under the selected one. Used by Insights (DS-3).
struct SectionIndex: View {
    let sections: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, title in
                let selected = index == selection
                Button {
                    selection = index
                } label: {
                    VStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? ProsperColor.ink : ProsperColor.ink3)
                        Rectangle()
                            .fill(selected ? ProsperColor.slate : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
