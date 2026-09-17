import SwiftUI

/// Typographic roles for Prosper. Numbers are SF Rounded and tabular; the one
/// "sentence you read" (insights) is serif; labels are small uppercase caps.
enum ProsperFont {
    static func hero(_ size: CGFloat = 48) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static let insight = Font.system(.title3, design: .serif)
    static let body = Font.body
    static let dataRow = Font.system(.subheadline).monospacedDigit()
}

extension View {
    /// 11pt, uppercase, wide tracking, tertiary ink — for section/eyebrow labels.
    func labelCaps() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(ProsperColor.ink3)
    }
}

/// A ready-made caps label.
struct LabelCaps: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).labelCaps()
    }
}
