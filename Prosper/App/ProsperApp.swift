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
                            }
                    } else {
                        AuthorizationView(authManager: authManager)
                    }
                }
            }
            .modelContainer(PersistenceConfig.sharedModelContainer)
            .onChange(of: scenePhase) { _, phase in
                // Returning to the app is the reliable moment to lift a block whose
                // timer elapsed while the system monitor didn't fire.
                if phase == .active { BlockingService.shared.clearExpiredBlockIfNeeded() }
            }
        }
    }

    /// Re-installs the waste-time DeviceActivity monitor on launch so a device
    /// reboot or app reinstall does not silently drop it.
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

@MainActor
class AuthorizationManager: ObservableObject {
    @Published var isAuthorized = false

    init() {
        #if targetEnvironment(simulator)
        isAuthorized = true
        #else
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        #endif
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }
}
