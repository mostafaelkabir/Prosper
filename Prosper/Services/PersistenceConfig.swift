import Foundation
import SwiftData
@preconcurrency import DeviceActivity

/// What happened the last time the shared store was opened.
///
/// A store that will not open is the one failure the user can neither see nor
/// fix, so it is recorded in the App Group rather than only logged: the app
/// reads it on launch and says plainly what was lost. Written by both the app
/// and `ProsperMonitor`, whichever opens the store first.
enum PersistenceHealth: String, Sendable {
    /// The shared App Group store opened normally.
    case healthy
    /// The store could not be opened and was moved aside; Prosper started over
    /// with an empty one. History is gone, an active block is not.
    case recoveredFreshStore
    /// The App Group container was unavailable, so this launch is using a
    /// private store. Data written here is invisible to the extensions.
    case fellBackToLocalStore
    /// Nothing on disk would open. This launch keeps everything in memory and
    /// loses it on quit.
    case inMemoryOnly

    /// True when the user has lost data they might otherwise expect to see.
    var needsExplaining: Bool { self != .healthy }

    /// One sentence for the user. No jargon, no blame, no false comfort.
    var message: String? {
        switch self {
        case .healthy:
            return nil
        case .recoveredFreshStore:
            return "Prosper could not read its saved history, so it started a fresh one. Your past sessions and warnings are gone. Any block that is running is unaffected — it is enforced by iOS, not by this file."
        case .fellBackToLocalStore:
            return "Prosper could not reach its shared storage this launch, so history may look incomplete until you reopen the app. Any block that is running is unaffected."
        case .inMemoryOnly:
            return "Prosper could not open its storage at all, so nothing recorded this session will be kept. Any block that is running is unaffected. Reinstalling the app usually fixes this — note that reinstalling also ends any active block."
        }
    }
}

enum PersistenceConfig {
    static let appGroupID = "group.com.mostafa.prosper"
    nonisolated(unsafe) static let unblockActivityName = DeviceActivityName("prosper.unblock")
    /// A second, independent interval that ends a few minutes after the block
    /// does. If the primary `prosper.unblock` interval is never delivered, this
    /// one still wakes the monitor so the shield comes down (REL-7).
    nonisolated(unsafe) static let unblockSafetyActivityName = DeviceActivityName("prosper.unblock.safety")
    /// Daily interval that watches the waste selection and fires one event per
    /// rung of the warning ladder (see `WarningLevel`).
    nonisolated(unsafe) static let wasteActivityName = DeviceActivityName("prosper.waste")

    private static let healthKey = "persistence.health"

    /// How the store opened on this launch. Defaults to `.healthy` until the
    /// container is first touched.
    static var health: PersistenceHealth {
        guard let raw = UserDefaults(suiteName: appGroupID)?.string(forKey: healthKey),
              let state = PersistenceHealth(rawValue: raw) else { return .healthy }
        return state
    }

    private static func record(_ state: PersistenceHealth) {
        UserDefaults(suiteName: appGroupID)?.set(state.rawValue, forKey: healthKey)
    }

    /// Clears the warning once the user has read it, so it is shown once rather
    /// than on every launch forever.
    static func acknowledgeHealth() {
        UserDefaults(suiteName: appGroupID)?.set(PersistenceHealth.healthy.rawValue, forKey: healthKey)
    }

    static let schema = Schema([
        BlockSession.self,
        UsageStat.self,
        WarningEvent.self,
        UserSettings.self,
    ])

    /// The shared store, opened defensively.
    ///
    /// A `ModelContainer` that refuses to open — a bad migration, a truncated
    /// file, a container the OS has not mounted yet — used to be a `fatalError`,
    /// i.e. a guaranteed crash on launch with no way out from inside the app.
    /// Losing history is bad; being unable to open Prosper at all is worse, and
    /// it would leave a user with an active block and no screen that explains
    /// it. So we descend a ladder and record which rung we landed on.
    static let sharedModelContainer: ModelContainer = {
        // 1. The normal path: the shared App Group store.
        if let container = try? ModelContainer(for: schema, configurations: [configuration(at: sharedStoreURL)]) {
            return container
        }

        // 2. The store exists but will not open. Move it aside (keeping it for
        //    diagnosis rather than deleting the user's data outright) and start
        //    a fresh one in its place.
        if archiveUnreadableStore(at: sharedStoreURL),
           let container = try? ModelContainer(for: schema, configurations: [configuration(at: sharedStoreURL)]) {
            record(.recoveredFreshStore)
            return container
        }

        // 3. The App Group container itself is unreachable. A private store at
        //    least keeps the app usable for this launch.
        if let container = try? ModelContainer(for: schema, configurations: [configuration(at: localStoreURL)]) {
            record(.fellBackToLocalStore)
            return container
        }

        // 4. Nothing on disk works. Stay open, in memory, and say so.
        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ) {
            record(.inMemoryOnly)
            return container
        }

        // Rung 4 fails only when the schema itself is invalid — a build-time
        // mistake in the `@Model` types, which fails identically on every device
        // and cannot appear in the field without appearing in development first.
        preconditionFailure("SwiftData rejected the Prosper schema; this is a build error, not a device condition.")
    }()

    private static func configuration(at url: URL) -> ModelConfiguration {
        ModelConfiguration("Prosper", schema: schema, url: url, allowsSave: true)
    }

    static var sharedStoreURL: URL {
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        return containerURL.appendingPathComponent("Prosper.store")
    }

    /// Per-process store used when the App Group container cannot be reached.
    private static var localStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Prosper-local.store")
    }

    /// Renames the unreadable store (and SQLite's sidecar files) out of the way.
    /// Returns false if nothing could be moved, in which case a fresh store at
    /// the same URL would fail for the same reason.
    private static func archiveUnreadableStore(at url: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return false }

        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        var movedAny = false
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard manager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: url.path + suffix + ".unreadable-\(stamp)")
            if (try? manager.moveItem(at: source, to: destination)) != nil {
                movedAny = true
            } else {
                // Could not move it; deleting is the only way to make room.
                movedAny = ((try? manager.removeItem(at: source)) != nil) || movedAny
            }
        }
        return movedAny
    }
}
