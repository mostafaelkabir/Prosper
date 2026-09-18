import SwiftUI

/// Prosper's colour system — the approved **Aurora** palette (2026-09-17).
/// Defined in code (not an asset catalog) so the same tokens compile into the
/// app and the report extension without a shared catalog. Each token resolves
/// light/dark at runtime.
///
/// The four time classes are strict and shared everywhere:
/// `productive` (mint), `distracting` (coral), `rest` (cyan), `unclassified`
/// (muted). `accent` (violet) is the brand accent and NEVER means productivity.
enum ProsperColor {
    // MARK: Aurora surfaces & text
    static let background = dynamic(dark: 0x090D18, light: 0xF3F2FC)
    static let surface    = dynamic(dark: 0x141B2B, light: 0xFFFFFF)
    /// A slightly elevated fill for chips / inner tiles.
    static let surface2   = dynamic(dark: 0x1C2740, light: 0xECEAF9)
    static let ink        = dynamic(dark: 0xF0F3FF, light: 0x1C2440)
    static let ink2       = dynamic(dark: 0xA8B3CD, light: 0x5C6680)
    static let line       = dynamic(dark: 0x28334B, light: 0xE0E4F0)

    // MARK: Brand + on-accent
    static let accent     = dynamic(dark: 0xA58AFF, light: 0x6144DE)
    static let onAccent   = dynamic(dark: 0x111524, light: 0xFFFFFF)

    // MARK: The four time classes
    static let productive    = dynamic(dark: 0x58E4B3, light: 0x087B60)
    static let distracting   = dynamic(dark: 0xFF8974, light: 0xBD4438)
    static let rest          = dynamic(dark: 0x64CBE6, light: 0x197797)
    static let unclassified  = dynamic(dark: 0x7D8DA9, light: 0x768195)

    // MARK: Back-compat aliases (DS-1 names, now Aurora)
    /// The old DS-1 tokens are kept as aliases so existing consumers pick up
    /// Aurora without edits. New code should use the semantic names above.
    static let ground = background
    static let card   = surface
    static let card2  = surface2
    static let ink3   = unclassified
    static let slate  = accent
    static let ember  = distracting
    static let sage   = productive

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
