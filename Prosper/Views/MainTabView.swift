import SwiftUI
import SwiftData

struct MainTabView: View {
    enum Tab: Hashable { case today, insights, lock, settings }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .today
    @State private var showSetup = false
    @State private var didCheckSetup = false
    /// The level-3 intervention ProsperMonitor recorded while the app was away.
    @State private var intervention: WarningInterventionState.Pending?

    var body: some View {
        tabs
            .fullScreenCover(item: $intervention) { pending in
                InterventionView(
                    minutes: pending.minutes,
                    requiresPhrase: UserSettings.current(context: modelContext).level3PhraseRequired,
                    onLockItDown: {
                        selectedTab = .lock
                        intervention = nil
                    },
                    onAcknowledge: { intervention = nil }
                )
            }
            .onChange(of: scenePhase) { _, phase in
                // The warning usually fires while Prosper is in the background,
                // so coming back to the foreground is when we owe the screen.
                if phase == .active { refreshIntervention() }
            }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onResumeSetup: { showSetup = true })
                .tabItem {
                    Label("Today", systemImage: "clock")
                }
                .tag(Tab.today)

            StatsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
                .tag(Tab.insights)

            BlockView()
                .tabItem {
                    Label("Lock", systemImage: "lock.fill")
                }
                .tag(Tab.lock)

            SettingsView(onOpenSetup: { showSetup = true })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(ProsperColor.slate)
        .fullScreenCover(isPresented: $showSetup) {
            SetupFlowView()
        }
        .onAppear {
            presentSetupIfNeeded()
            refreshIntervention()
        }
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

    /// Pick up a pending intervention, unless onboarding is already in front —
    /// a first-run user has nothing to be confronted with yet.
    private func refreshIntervention() {
        guard !showSetup, intervention == nil else { return }
        intervention = WarningInterventionState.pending
    }
}
