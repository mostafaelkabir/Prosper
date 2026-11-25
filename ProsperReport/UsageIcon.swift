import SwiftUI
import FamilyControls
import ManagedSettings

// MARK: - Brand colours

extension Platform {
    /// The platform's brand colour.
    var tint: Color {
        Color(
            red: Double((tintHex >> 16) & 0xFF) / 255,
            green: Double((tintHex >> 8) & 0xFF) / 255,
            blue: Double(tintHex & 0xFF) / 255
        )
    }

    /// Black or white, whichever stays readable on `tint` (Snapchat yellow needs
    /// a dark glyph, YouTube red a light one).
    var onTint: Color {
        let r = Double((tintHex >> 16) & 0xFF) / 255
        let g = Double((tintHex >> 8) & 0xFF) / 255
        let b = Double(tintHex & 0xFF) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? .black : .white
    }
}

// MARK: - The mark on a usage row

/// The logo for one row of usage — an app, a platform, or a website.
///
/// On a real device the report extension holds the system `ApplicationToken`,
/// and FamilyControls draws **Apple's own app icon** for it: the real YouTube,
/// Instagram or WhatsApp logo, rendered by the system rather than shipped by us.
/// Where iOS gives no token — a website the user only browses, the simulator's
/// example data — we draw the platform's brand tile instead, and anything we
/// don't recognise falls back to a neutral monogram. The row always has a mark.
struct UsageIcon: View {
    var appToken: ApplicationToken?
    var webToken: WebDomainToken?
    var platformID: String?
    var name: String
    var size: CGFloat = 34
    /// Drawn instead of the name's initial when there is nothing to identify —
    /// a category row is "Social", not an app, so a letter would mislead.
    var fallbackSymbol: String? = nil

    private var platform: Platform? {
        if let platformID { return PlatformCatalog.platform(id: platformID) }
        return PlatformCatalog.match(name)
    }

    var body: some View {
        Group {
            if let appToken {
                systemIcon(Label(appToken))
            } else if let platform {
                BrandMark(platform: platform, size: size)
            } else if let webToken {
                systemIcon(Label(webToken))
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // the row's name text already says which app this is
    }

    /// Apple's rendering of the token, cropped to a rounded app-icon shape.
    private func systemIcon<L: View>(_ label: L) -> some View {
        label
            .labelStyle(.iconOnly)
            .font(.system(size: size))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
    }

    private var monogram: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(ProsperColor.surface2)
            .overlay(
                Group {
                    if let fallbackSymbol {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: size * 0.42, weight: .medium))
                    } else {
                        Text(String(name.first.map(String.init) ?? "?").uppercased())
                            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundStyle(ProsperColor.ink2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .strokeBorder(ProsperColor.line, lineWidth: 0.5)
            )
    }
}

/// A platform's brand tile: its colour and its own mark, with a hairline so
/// near-black brands (X, TikTok) stay visible on the dark theme.
///
/// The marks are bundled (`BrandLogos.xcassets`, built from Simple Icons by
/// `scripts/make-brand-logos.py`), never downloaded. They are their owners'
/// trademarks and are drawn only to say which app or site a row is. A
/// platform with no bundled mark falls back to its SF Symbol.
struct BrandMark: View {
    let platform: Platform
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(platform.tint)
            .overlay(mark.foregroundStyle(platform.onTint))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .strokeBorder(ProsperColor.line.opacity(0.6), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var mark: some View {
        if BrandLogo.platforms.contains(platform.id) {
            Image(BrandLogo.imageName(platform.id))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.58, height: size * 0.58)
        } else {
            Image(systemName: platform.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
        }
    }
}

/// The brand marks in `BrandLogos.xcassets`, by catalog platform id.
enum BrandLogo {
    static let platforms: Set<String> = [
        "facebook", "instagram", "youtube", "tiktok", "x", "reddit", "snapchat", "whatsapp",
        "netflix", "twitch", "pinterest", "linkedin", "zoom", "slack", "teams", "gmail",
    ]

    static func imageName(_ platformID: String) -> String { "brand-" + platformID }
}

extension UsageIcon {
    init(_ item: UsageItem, size: CGFloat = 34, fallbackSymbol: String? = nil) {
        self.init(
            appToken: item.appToken,
            webToken: item.webToken,
            platformID: item.platformID,
            name: item.name,
            size: size,
            fallbackSymbol: fallbackSymbol
        )
    }
}
