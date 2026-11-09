import SwiftUI

@main
struct ProsperMacApp: App {
    @StateObject private var model = AppModel()

    init() {
        #if DEBUG
        SnapshotRenderer.runIfRequested()
        #endif
    }

    var body: some Scene {
        Window("StolenEyes", id: "main") {
            RootView()
                .environmentObject(model)
                .onAppear {
                    model.setup.refresh()
                    // Put back a filter someone switched off, and keep the helper registered.
                    if model.settings.onboarded {
                        model.setup.registerAgent()
                        model.setup.updateExtension()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.setup.reassert() }
                    }
                }
        }
        .defaultSize(width: 980, height: 760)

        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: model.lockEndsAt != nil ? "lock.fill" : "eye")
        }
    }
}
