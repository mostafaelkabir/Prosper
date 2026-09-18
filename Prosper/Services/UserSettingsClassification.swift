import Foundation

// This extension lives in the app target only (not the ProsperMonitor extension,
// which also compiles the UserSettings model), because it depends on
// `WasteSelectionCodec` and `SharedClassification`.
extension UserSettings {
    /// Mirror the four-class classification into the shared App Group so the
    /// ProsperReport extension can build a real `TimeBalance`. Distracting is the
    /// waste selection. Call after any change to a class's apps or domains.
    func syncClassificationSnapshot() {
        SharedClassification.save(
            productive: WasteSelectionCodec.decode(productiveSelectionData),
            distracting: WasteSelectionCodec.decode(wasteAppSelectionData),
            rest: WasteSelectionCodec.decode(restSelectionData),
            productiveDomains: productiveDomains,
            distractingDomains: wasteDomains,
            restDomains: restDomains
        )
    }
}
