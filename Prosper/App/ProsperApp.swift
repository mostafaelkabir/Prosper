import SwiftUI
import SwiftData
import FamilyControls

@main
struct ProsperApp: App {
    @StateObject private var authManager = AuthorizationManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthorized {
                    MainTabView()
                        .onAppear {
                            UsageTrackingService.shared.startDailyMonitoring()
                            refreshWarningSchedule()
                        }
                } else {
                    AuthorizationView(authManager: authManager)
                }
            }
            .modelContainer(PersistenceConfig.sharedModelContainer)
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
