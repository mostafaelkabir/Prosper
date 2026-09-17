import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showSetup = false
    @State private var didCheckSetup = false

    var body: some View {
        TabView {
            DashboardView(onResumeSetup: { showSetup = true })
                .tabItem {
                    Label("Today", systemImage: "clock")
                }

            StatsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }

            BlockView()
                .tabItem {
                    Label("Lock", systemImage: "lock.fill")
                }

            SettingsView(onOpenSetup: { showSetup = true })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(ProsperColor.slate)
        .fullScreenCover(isPresented: $showSetup) {
            SetupFlowView()
        }
        .onAppear(perform: presentSetupIfNeeded)
    }

    /// Show the setup flow once per launch until the user finishes or skips it.
    private func presentSetupIfNeeded() {
        guard !didCheckSetup else { return }
        didCheckSetup = true
        let settings = UserSettings.current(context: modelContext)
        if !settings.hasCompletedSetup {
            showSetup = true
        }
    }
}
