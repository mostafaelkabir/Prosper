import SwiftUI

/// Prosper's colour system. Defined in code (not an asset catalog) so the same
/// tokens compile into the app and the report extension without a shared
/// catalog. Each token resolves light/dark at runtime.
///
/// Semantics are strict: `slate` is the accent and "everything else", `ember`
/// is waste-only, `sage` is good. Never reach for `.orange` / `.green` / `.red`.
enum ProsperColor {
    static let ground = dynamic(dark: 0x0F1115, light: 0xF6F5F2)
    static let card   = dynamic(dark: 0x171A20, light: 0xFFFFFF)
    static let card2  = dynamic(dark: 0x1E222A, light: 0xEFEDE8)

    static let ink    = dynamic(dark: 0xF6F5F2, light: 0x14161A)
    static let ink2   = dynamic(dark: 0xB8BCC6, light: 0x4A4F59)
    static let ink3   = dynamic(dark: 0x7A8091, light: 0x8A8F99)
    static let line   = dynamic(dark: 0x262A32, light: 0xE2E0DA)

    /// Accent + neutral "everything else" on charts.
    static let slate  = dynamic(dark: 0x7088CC, light: 0x4F65A3)
    /// Waste only.
    static let ember  = dynamic(dark: 0xE85A33, light: 0xE4552B)
    /// Good / under-goal.
    static let sage   = dynamic(dark: 0x5FAE72, light: 0x3E9A5B)

    private static func dynamic(dark: UInt, light: UInt) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
