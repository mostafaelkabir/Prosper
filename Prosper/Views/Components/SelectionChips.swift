import SwiftUI
import FamilyControls
import ManagedSettings

/// Wrapping chip row that shows the real app / category / website icons and
/// names for a `FamilyActivitySelection`, using the `Label(token)` views that
/// FamilyControls renders inside an authorized app. On the simulator the token
/// set is always empty (FamilyControls authorization is device-only), so it
/// falls back to a single count chip. Typed domains — which live in the web
/// content filter, not the token set — render as globe chips.
struct SelectionChips: View {
    let selection: FamilyActivitySelection
    /// Websites the user typed by hand (e.g. "reddit.com").
    var typedDomains: [String] = []
    /// Count shown on the simulator fallback chip when no tokens are available.
    var placeholderCount: Int = 0
    /// Maximum chips shown before the rest collapse into a "+N more" chip.
    var cap: Int = 8

    private enum Item: Hashable {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)
        case web(WebDomainToken)
        case domain(String)
    }

    private var items: [Item] {
        var result: [Item] = []
        result += selection.applicationTokens.map(Item.app)
        result += selection.categoryTokens.map(Item.category)
        result += selection.webDomainTokens.map(Item.web)
        result += typedDomains.map(Item.domain)
        return result
    }

    var body: some View {
        let items = items
        if items.isEmpty {
            if placeholderCount > 0 {
                ChipShape {
                    Text("\(placeholderCount) selected")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            let shown = Array(items.prefix(cap))
            let overflow = items.count - shown.count
            FlowLayout(spacing: 8) {
                ForEach(shown, id: \.self) { item in
                    chip(for: item)
                }
                if overflow > 0 {
                    ChipShape {
                        Text("+\(overflow) more")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for item: Item) -> some View {
        switch item {
        case .app(let token):
            ChipShape { Label(token).labelStyle(.titleAndIcon) }
        case .category(let token):
            ChipShape { Label(token).labelStyle(.titleAndIcon) }
        case .web(let token):
            ChipShape { Label(token).labelStyle(.titleAndIcon) }
        case .domain(let domain):
            ChipShape { Label(domain, systemImage: "globe") }
        }
    }
}

/// Capsule chip wrapper matching the app's existing pill styling.
private struct ChipShape<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .imageScale(.small)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}

/// Lays subviews left to right, wrapping to a new line when the next one would
/// overflow the proposed width. Used for the selection chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth)
        let width = maxWidth == .infinity ? maxRowWidth : maxWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
