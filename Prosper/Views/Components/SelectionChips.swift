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
    /// Bigger chips with bigger icons, for the lists a person builds (UX-28).
    var large = false

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
                Chip(large: large) {
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
                    Chip(large: large) {
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
            Chip(large: large) { Label(token).labelStyle(.titleAndIcon) }
        case .category(let token):
            Chip(large: large) { Label(token).labelStyle(.titleAndIcon) }
        case .web(let token):
            Chip(large: large) { Label(token).labelStyle(.titleAndIcon) }
        case .domain(let domain):
            // The explicit style matters inside a Form: a list row lays a
            // plain Label out in its own icon column and the name fell
            // outside the chip.
            Chip(large: large) {
                SiteLabel(domain: domain, iconSize: large ? 22 : 18, named: large)
                    .labelStyle(.titleAndIcon)
            }
        }
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

/// A typed website with its icon: the platform's brand tile when the catalog
/// knows the site (reddit.com, youtu.be…), a lettered tile otherwise. iOS gives
/// typed domains no icon of their own, unlike app and web tokens (UX-22).
///
struct SiteLabel: View {
    let domain: String
    var iconSize: CGFloat = 22
    /// Says "YouTube" instead of "youtube.com" for a platform's main address.
    /// For the lists a person builds; a review of what gets locked keeps the
    /// exact addresses.
    var named = false

    private var title: String {
        guard named else { return domain }
        return PlatformCatalog.all.first { $0.domains.first == domain }?.name ?? domain
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SiteIcon(domain: domain, size: iconSize)
        }
    }
}

struct SiteIcon: View {
    let domain: String
    var size: CGFloat = 22

    var body: some View {
        if let platform = PlatformCatalog.match(domain) {
            BrandMark(platform: platform, size: size)
        } else {
            // The site's initial on a colour of its own, so a list of typed
            // sites is told apart at a glance instead of being a row of globes
            // (UX-28). The app never goes online for a site's real icon.
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(SiteTint.color(for: domain))
                .overlay(
                    Text(SiteTint.initial(for: domain))
                        .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// The colour and letter drawn for a site the catalog does not know.
enum SiteTint {
    /// Dark enough that the white initial stays readable on every one (each
    /// is at least 4.5:1 against white).
    static let palette: [UInt] = [0x4F46E5, 0x0F766E, 0xB45309, 0xBE185D, 0x1D4ED8, 0x6D28D9, 0x047857, 0x475569]

    /// Always the same colour for the same site, on every launch and device:
    /// `Hasher` is seeded per launch, so the sum is done by hand.
    static func index(for domain: String) -> Int {
        let sum = domain.lowercased().unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Int(sum % UInt32(palette.count))
    }

    static func color(for domain: String) -> Color {
        let hex = palette[index(for: domain)]
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func initial(for domain: String) -> String {
        domain.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "?"
    }
}
