import Foundation
import SwiftData

/// "Delete my data" (REL-13).
///
/// Wipes everything Prosper has stored on this device — usage history, warning
/// history, block history, settings and every shared snapshot — with one
/// deliberate exception: a block that is still running is left exactly as it is.
///
/// That exception is the whole design. Deleting data must not become the cancel
/// button the app promises does not exist, and it very nearly could: the expiry
/// sweep decides whether a block is still live by reading the App Group
/// snapshot and the stored sessions, so wiping both would read as "nothing is
/// running" and take the shield down. The block's own record survives; the user
/// keeps the commitment they made and loses only the history around it.
enum DataReset {

    struct Outcome {
        /// True when a running block was deliberately left in place.
        let keptActiveBlock: Bool
    }

    @MainActor
    @discardableResult
    static func deleteEverything(context: ModelContext) -> Outcome {
        let activeBlock = SharedBlockState.active

        // 1. History. Block sessions are filtered in code rather than by
        //    predicate because "still running" is a comparison against now.
        let sessions = (try? context.fetch(FetchDescriptor<BlockSession>())) ?? []
        for session in sessions where !session.isActive {
            context.delete(session)
        }
        try? context.delete(model: UsageStat.self)
        try? context.delete(model: WarningEvent.self)
        try? context.delete(model: UserSettings.self)
        try? context.save()

        // 2. Shared snapshots, minus the active block's.
        SharedClassification.clear()
        WarningInterventionState.clear()
        WarningDeliveryLedger.appGroup?.clear()
        SetupSkip.clear()
        PersistenceConfig.acknowledgeHealth()
        if activeBlock == nil {
            SharedBlockState.clear()
        }

        // 3. Stop watching for waste time — there is no waste list any more.
        //    The unblock schedules are untouched, so a running block still ends
        //    on its own.
        WarningService.shared.stop()

        return Outcome(keptActiveBlock: activeBlock != nil)
    }
}
