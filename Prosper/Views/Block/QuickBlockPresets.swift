import Foundation
import FamilyControls
import SwiftData

/// A ready-to-start block generated from a saved preset. Feeds `CreateBlockView`.
struct BlockPrefill: Equatable, Identifiable {
    let id = UUID()
    var selection: FamilyActivitySelection
    var domains: [String]
    var duration: TimeInterval
}

/// One-tap "Focus for N" presets that block the user's saved waste selection
/// (apps + typed sites from Settings) for a fixed duration. Presets are only
/// useful when the user has configured a waste list.
struct QuickPreset: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let systemImage: String
    let duration: TimeInterval

    static let all: [QuickPreset] = [
        QuickPreset(label: "1h", systemImage: "1.circle.fill", duration: 3600),
        QuickPreset(label: "2h", systemImage: "2.circle.fill", duration: 7200),
        QuickPreset(label: "4h", systemImage: "4.circle.fill", duration: 14400),
    ]

    func prefill(from settings: UserSettings) -> BlockPrefill {
        BlockPrefill(
            selection: WasteSelectionCodec.decode(settings.wasteAppSelectionData),
            domains: settings.wasteDomains,
            duration: duration
        )
    }
}
