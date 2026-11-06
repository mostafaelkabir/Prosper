import Foundation
import SwiftData

/// Starter sites for the waste list, so a fresh install can lock the usual
/// feeds from the Lock tab's Focus buttons without typing a domain (UX-21).
enum WasteDefaults {
    /// Batches of starter sites, oldest first. A batch added in a later
    /// release reaches existing installs once, on their next launch.
    static let batches: [(version: Int, domains: [String])] = [
        // Every platform the catalog already files as distracting.
        (1, PlatformCatalog.all.filter { $0.defaultClass == .distracting }.flatMap(\.domains)),
        // Asked for by name; the catalog leaves YouTube unclassified because
        // it is also how people learn (UX-22).
        (2, ["youtube.com", "youtu.be"]),
    ]

    static var domains: [String] { batches.flatMap(\.domains) }
    static var latestVersion: Int { batches.map(\.version).max() ?? 0 }

    /// Offers every batch this install has not seen. A fresh install gets the
    /// lot. An install whose user had built a list before starters existed
    /// keeps it untouched apart from batches newer than the first.
    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let settings = UserSettings.current(context: context)
        let seen = settings.wasteSeedVersion
        guard seen < latestVersion else { return }

        let firstOffered = (seen == 0 && !settings.wasteDomains.isEmpty) ? 2 : seen + 1
        var list = settings.wasteDomains
        for batch in batches where batch.version >= firstOffered {
            list += batch.domains.filter { !list.contains($0) }
        }
        settings.wasteDomains = Array(list.prefix(BlockingService.maxDomains))
        settings.wasteSeedVersion = latestVersion
        try? context.save()
    }
}
