import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showSetup = false
    @State private var didCheckSetup = false

    var body: some View {
        TabView {
            DashboardView(onResumeSetup: { showSetup = true })
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }

            BlockView()
                .tabItem {
                    Label("Block", systemImage: "lock.fill")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView(onOpenSetup: { showSetup = true })
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
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
