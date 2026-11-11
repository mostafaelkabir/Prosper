import SwiftUI

/// Typographic roles for Prosper. Numbers are SF Rounded and tabular; the one
/// "sentence you read" (insights) is serif; labels are small uppercase caps.
public enum ProsperFont {
    public static func hero(_ size: CGFloat = 48) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    public static let insight = Font.system(.title3, design: .serif)
    public static let body = Font.body
    public static let dataRow = Font.system(.subheadline).monospacedDigit()
}

/// A system font at a designed size that grows and shrinks with the user's
/// text size (Dynamic Type) on iPhone, relative to the nearest text style.
/// macOS has no Dynamic Type, so on the Mac it is exactly the designed size.
public struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    public init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.style(for: size))
        self.weight = weight
        self.design = design
    }

    public func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    /// The text style whose default size is closest, so each size scales
    /// at the same rate as its system counterpart.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}

public extension View {
    /// Use instead of `.font(.system(size:))` for text, so it follows Dynamic Type.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }

    /// 11pt, uppercase, wide tracking, tertiary ink — for section/eyebrow labels.
    func labelCaps() -> some View {
        self
            .scaledFont(11, weight: .semibold)
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(ProsperColor.ink3)
    }
}

/// A ready-made caps label.
public struct LabelCaps: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).labelCaps()
    }
}
