import Foundation
import FamilyControls
import SwiftData

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

extension UserSettings {
    /// A fingerprint of every label. A hosted report is cached by iOS on
    /// (context, filter) and only reads the labels when it is built, so a
    /// screen that shows labelled time folds this into the report's `.id` to
    /// have it rebuilt after a label changes.
    var labelSignature: Int {
        var hasher = Hasher()
        hasher.combine(wasteAppSelectionData)   // distracting apps
        hasher.combine(wasteDomains)            // distracting sites
        hasher.combine(productiveSelectionData)
        hasher.combine(productiveDomains)
        hasher.combine(restSelectionData)
        hasher.combine(restDomains)
        return hasher.finalize()
    }
}

// MARK: - The block list (UX-28)

extension UserSettings {
    /// The block list is the Distracting class: what the Lock tab locks, what
    /// warnings count, and what the day's hours are filed under as waste.
    var blockListSelection: FamilyActivitySelection {
        WasteSelectionCodec.decode(wasteAppSelectionData)
    }

    /// Saves the block list and everything that follows from it: the label
    /// snapshot the report extension reads, and the warning monitor. Anything
    /// put on the list stops being Productive or Rest, so one app never
    /// carries two labels.
    func saveBlockList(selection: FamilyActivitySelection, domains: [String], context: ModelContext) {
        wasteAppSelectionData = WasteSelectionCodec.encode(selection)
        wasteAppCount = selection.applicationTokens.count + selection.categoryTokens.count
        wasteDomains = domains
        productiveDomains.removeAll { domains.contains($0) }
        restDomains.removeAll { domains.contains($0) }
        if productiveSelectionData != nil {
            productiveSelectionData = WasteSelectionCodec.encode(
                LabelSets.removing(selection, from: WasteSelectionCodec.decode(productiveSelectionData)))
        }
        if restSelectionData != nil {
            restSelectionData = WasteSelectionCodec.encode(
                LabelSets.removing(selection, from: WasteSelectionCodec.decode(restSelectionData)))
        }
        try? context.save()
        syncClassificationSnapshot()
        WarningService.shared.refreshSchedule(
            enabled: warningsEnabled,
            selection: selection,
            typedDomains: domains,
            thresholdMinutes: wasteWarningThresholdMinutes
        )
    }
}

/// Keeps the three labels apart: an app, category or site has one at a time.
enum LabelSets {
    /// `other` without anything that `taken` now holds.
    static func removing(_ taken: FamilyActivitySelection, from other: FamilyActivitySelection) -> FamilyActivitySelection {
        var result = other
        result.applicationTokens.subtract(taken.applicationTokens)
        result.categoryTokens.subtract(taken.categoryTokens)
        result.webDomainTokens.subtract(taken.webDomainTokens)
        return result
    }

    /// What `new` holds that `old` did not.
    static func added(in new: FamilyActivitySelection, since old: FamilyActivitySelection) -> FamilyActivitySelection {
        removing(old, from: new)
    }

    static func isEmpty(_ selection: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }
}
