import SwiftUI
import SwiftData
import FamilyControls
import UserNotifications

@main
struct ProsperApp: App {
    @StateObject private var authManager = AuthorizationManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Set before launch finishes, so a check-in button tapped on the lock
        // screen reaches the app when iOS starts it just to handle it (E10.1).
        UNUserNotificationCenter.current().delegate = CheckInNotificationDelegate.shared
        NightlyCheckInCenter.registerCategory()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Paint the app background on the very first frame so there is no
                // white gap between the launch screen and the first content (QA-3).
                ProsperColor.background.ignoresSafeArea()
                Group {
                    if authManager.isAuthorized {
                        MainTabView()
                            .onAppear {
                                WasteDefaults.seedIfNeeded(context: PersistenceConfig.sharedModelContainer.mainContext)
                                // Installing a DeviceActivity schedule waits on
                                // ProsperMonitor; on the main thread a stalled
                                // monitor froze launch until iOS killed it (QA-10).
                                DispatchQueue.global(qos: .utility).async {
                                    UsageTrackingService.shared.startDailyMonitoring()
                                    Self.refreshWarningSchedule()
                                }
                                BlockingService.shared.clearExpiredBlockIfNeeded()
                                ScheduledLockService.shared.reconcile()
                                // A running block whose timers were lost gets
                                // them back, so it can still end on its own.
                                BlockingService.shared.reassertScheduleIfNeeded()
                                // The guard is permanent; rewriting it on launch
                                // heals a restore or update that dropped it (E9).
                                AdultContentGuard.shared.reassertIfEnabled()
                                // Derived from the rule and the clock, so a
                                // callback iOS dropped is healed here (E9.6).
                                InstallWindowService.shared.reconcile()
                                // onChange(of: scenePhase) misses the first
                                // .active of a cold launch, so start here (M7.3).
                                ConnectedDevices.shared.appBecameActive()
                            }
                    } else {
                        AuthorizationView(authManager: authManager)
                    }
                }
            }
            .modelContainer(PersistenceConfig.sharedModelContainer)
            .onChange(of: scenePhase) { _, phase in
                // Connected devices (M7.3): send this iPhone's day to the Mac
                // and fetch the Mac's while open; one last send on the way out.
                if authManager.isAuthorized {
                    if phase == .active { ConnectedDevices.shared.appBecameActive() }
                    if phase == .background { ConnectedDevices.shared.appWentToBackground() }
                }
                guard phase == .active else { return }
                // Returning to the app is the reliable moment to lift a block whose
                // timer elapsed while the system monitor didn't fire.
                BlockingService.shared.clearExpiredBlockIfNeeded()
                ScheduledLockService.shared.reconcile()
                InstallWindowService.shared.reconcile()
                // Tops up the fortnight of check-in reminders (E10.1).
                NightlyCheckInCenter.shared.reload()
                // Screen Time access can be withdrawn in iOS Settings while
                // Prosper is in the background, so it is re-read here rather
                // than trusted from launch (REL-10).
                authManager.refresh()
            }
        }
        .backgroundTask(.appRefresh(ConnectedDevices.refreshTaskID)) {
            await ConnectedDevices.shared.syncNow()
            await ConnectedDevices.scheduleBackgroundRefresh()
        }
    }

    /// Makes sure the waste-time DeviceActivity monitor is installed on launch
    /// so a device reboot or app reinstall does not silently drop it. A monitor
    /// that is already running with the same settings is left alone rather than
    /// restarted, which used to reset the day's count on every cold launch (QA-9).
    nonisolated private static func refreshWarningSchedule() {
        let context = ModelContext(PersistenceConfig.sharedModelContainer)
        let settings = UserSettings.current(context: context)
        // Mirror existing labels into the App Group so the report extension can
        // build a real balance even for users who classified before this build.
        settings.syncClassificationSnapshot()
        WarningService.shared.refreshSchedule(
            enabled: settings.warningsEnabled,
            selection: WasteSelectionCodec.decode(settings.wasteAppSelectionData),
            typedDomains: settings.wasteDomains,
            thresholdMinutes: settings.wasteWarningThresholdMinutes
        )
    }
}
