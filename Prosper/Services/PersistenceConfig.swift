import Foundation
import SwiftData
@preconcurrency import DeviceActivity

enum PersistenceConfig {
    static let appGroupID = "group.com.mostafa.prosper"
    nonisolated(unsafe) static let unblockActivityName = DeviceActivityName("prosper.unblock")

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BlockSession.self,
            UsageStat.self,
            WarningEvent.self,
            UserSettings.self,
        ])

        let config = ModelConfiguration(
            "Prosper",
            schema: schema,
            url: sharedStoreURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }()

    static var sharedStoreURL: URL {
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        return containerURL.appendingPathComponent("Prosper.store")
    }
}
