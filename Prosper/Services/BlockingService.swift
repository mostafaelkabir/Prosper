import Foundation
import ManagedSettings
import FamilyControls

final class BlockingService {
    static let shared = BlockingService()

    private let store = ManagedSettingsStore()

    private init() {}

    func startBlock(
        apps: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        duration: TimeInterval
    ) {
        store.shield.applications = apps
        store.shield.webDomains = webDomains

        let endTime = Date.now.addingTimeInterval(duration)
        scheduleUnblock(at: endTime)
    }

    func clearBlock() {
        store.shield.applications = nil
        store.shield.webDomains = nil
    }

    var hasActiveBlock: Bool {
        store.shield.applications != nil || store.shield.webDomains != nil
    }

    private func scheduleUnblock(at date: Date) {
        let interval = date.timeIntervalSince(.now)
        guard interval > 0 else {
            clearBlock()
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(interval))
            await MainActor.run {
                clearBlock()
            }
        }
    }
}
