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
                } else {
                    AuthorizationView(authManager: authManager)
                }
            }
            .modelContainer(PersistenceConfig.sharedModelContainer)
        }
    }
}

@MainActor
class AuthorizationManager: ObservableObject {
    @Published var isAuthorized = false

    init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
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
