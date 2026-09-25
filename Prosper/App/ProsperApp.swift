import SwiftUI
import SwiftData
import FamilyControls

@main
struct ProsperApp: App {
    @StateObject private var authManager = AuthorizationManager()
    @Environment(\.scenePhase) private var scenePhase

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
                                UsageTrackingService.shared.startDailyMonitoring()
                                refreshWarningSchedule()
                                BlockingService.shared.clearExpiredBlockIfNeeded()
                                // A running block whose timers were lost gets
                                // them back, so it can still end on its own.
                                BlockingService.shared.reassertScheduleIfNeeded()
                            }
                    } else {
                        AuthorizationView(authManager: authManager)
                    }
                }
            }
            .modelContainer(PersistenceConfig.sharedModelContainer)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // Returning to the app is the reliable moment to lift a block whose
                // timer elapsed while the system monitor didn't fire.
                BlockingService.shared.clearExpiredBlockIfNeeded()
                // Screen Time access can be withdrawn in iOS Settings while
                // Prosper is in the background, so it is re-read here rather
                // than trusted from launch (REL-10).
                authManager.refresh()
            }
        }
    }

    /// Makes sure the waste-time DeviceActivity monitor is installed on launch
    /// so a device reboot or app reinstall does not silently drop it. A monitor
    /// that is already running with the same settings is left alone rather than
    /// restarted, which used to reset the day's count on every cold launch (QA-9).
    private func refreshWarningSchedule() {
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
