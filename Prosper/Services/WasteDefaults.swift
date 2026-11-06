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
        // Asked for by name (UX-22).
        (2, ["youtube.com", "youtu.be"]),
        // YouTube everywhere, its mobile site spelled out, and now also carried into
        // schedules and the New Block list: a Work focus schedule made before
        // batch 2 let m.youtube.com through (UX-24).
        (3, ["youtube.com", "youtu.be", "m.youtube.com"]),
    ]

    /// Every starter site once, in batch order.
    static var domains: [String] {
        var seen = Set<String>()
        return batches.flatMap(\.domains).filter { seen.insert($0).inserted }
    }
    static var latestVersion: Int { batches.map(\.version).max() ?? 0 }

    /// Offers every batch this install has not seen. A fresh install gets the
    /// lot. An install whose user had built a list before starters existed
    /// keeps it untouched apart from batches newer than the first. New
    /// batches also reach a saved New Block list and every schedule, which
    /// only ever adds to them, so it is allowed even mid-window (UX-24).
    @MainActor
    static func seedIfNeeded(context: ModelContext, schedules: ScheduledLockService? = .shared) {
        let settings = UserSettings.current(context: context)
        let seen = settings.wasteSeedVersion
        guard seen < latestVersion else { return }

        let firstOffered = (seen == 0 && !settings.wasteDomains.isEmpty) ? 2 : seen + 1
        let offered = batches.filter { $0.version >= firstOffered }.flatMap(\.domains)
        settings.wasteDomains = adding(offered, to: settings.wasteDomains)
        if !settings.savedBlockDomains.isEmpty {
            settings.savedBlockDomains = adding(offered, to: settings.savedBlockDomains)
        }
        if let schedules, firstOffered > 1 {
            schedules.addToAll(domains: offered)
        }
        settings.wasteSeedVersion = latestVersion
        try? context.save()
    }

    /// `list` plus whatever of `domains` it lacks, within iOS's filter limit.
    static func adding(_ domains: [String], to list: [String]) -> [String] {
        var result = list
        for domain in domains where !result.contains(domain) && result.count < BlockingService.maxDomains {
            result.append(domain)
        }
        return result
    }
}
