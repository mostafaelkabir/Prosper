import Foundation
import ManagedSettings
import FamilyControls
import DeviceActivity
import SwiftData

final class BlockingService {
    static let shared = BlockingService()

    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()

    static let unblockActivityName = DeviceActivityName("prosper.unblock")

    private init() {}

    func startBlock(
        apps: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        duration: TimeInterval
    ) {
        store.shield.applications = apps
        store.shield.webDomains = webDomains

        scheduleUnblock(duration: duration)
        persistBlockSession(appCount: apps.count, domainCount: webDomains.count, duration: duration)
    }

    func clearBlock() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        activityCenter.stopMonitoring([Self.unblockActivityName])
    }

    var hasActiveBlock: Bool {
        store.shield.applications != nil || store.shield.webDomains != nil
    }

    private func scheduleUnblock(duration: TimeInterval) {
        let endDate = Date.now.addingTimeInterval(duration)
        let endComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: endDate
        )
        let startComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: .now
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        do {
            try activityCenter.startMonitoring(Self.unblockActivityName, during: schedule)
        } catch {
            print("Failed to schedule unblock: \(error)")
        }
    }

    private func persistBlockSession(appCount: Int, domainCount: Int, duration: TimeInterval) {
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let session = BlockSession(
            blockedAppTokens: Array(repeating: "app", count: appCount),
            blockedWebDomains: Array(repeating: "domain", count: domainCount),
            duration: duration
        )
        context.insert(session)
        try? context.save()
    }
}
