import Foundation
import ManagedSettings
import FamilyControls
import DeviceActivity
import SwiftData

final class BlockingService: @unchecked Sendable {
    static let shared = BlockingService()

    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()

    private init() {}

    func startBlock(
        apps: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        duration: TimeInterval,
        selection: FamilyActivitySelection
    ) {
        guard !hasActiveBlock else { return }

        store.shield.applications = apps
        store.shield.webDomains = webDomains

        scheduleUnblock(duration: duration)
        persistBlockSession(selection: selection, appCount: apps.count, domainCount: webDomains.count, duration: duration)
    }

    func clearBlock() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        activityCenter.stopMonitoring([PersistenceConfig.unblockActivityName])
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
            try activityCenter.startMonitoring(PersistenceConfig.unblockActivityName, during: schedule)
        } catch {
            print("Failed to schedule unblock: \(error)")
        }
    }

    private func persistBlockSession(selection: FamilyActivitySelection, appCount: Int, domainCount: Int, duration: TimeInterval) {
        let container = PersistenceConfig.sharedModelContainer
        let context = ModelContext(container)
        let selectionData = try? JSONEncoder().encode(selection)
        let session = BlockSession(
            appCount: appCount,
            domainCount: domainCount,
            selectionData: selectionData,
            duration: duration
        )
        context.insert(session)
        try? context.save()
    }
}
