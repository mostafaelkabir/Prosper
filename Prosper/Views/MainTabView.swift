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
    /// What the store lost on this launch, if anything. Shown once, before
    /// setup or an intervention can cover it (QA-9).
    @State private var storageNotice: String?

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
            .alert(
                "Some history was lost",
                isPresented: Binding(
                    get: { storageNotice != nil },
                    set: { if !$0 { acknowledgeStorageNotice() } }
                )
            ) {
                Button("OK") { acknowledgeStorageNotice() }
            } message: {
                Text(storageNotice ?? "")
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
        // An intervention that fired while setup was open is owed the moment
        // setup closes, not at the next foreground (QA-9).
        .fullScreenCover(isPresented: $showSetup, onDismiss: refreshIntervention) {
            SetupFlowView()
        }
        .onAppear {
            // PersistenceConfig records a store it had to recover or replace;
            // until now nothing read it, so lost history went unexplained
            // (QA-9). The notice goes first; setup follows once it is read.
            let health = PersistenceConfig.health
            if health.needsExplaining, let message = health.message {
                storageNotice = message
                return
            }
            presentSetupIfNeeded()
            refreshIntervention()
        }
    }

    private func acknowledgeStorageNotice() {
        guard storageNotice != nil else { return }
        storageNotice = nil
        PersistenceConfig.acknowledgeHealth()
        presentSetupIfNeeded()
        refreshIntervention()
    }

    /// Show the setup flow automatically only until the user finishes or
    /// skips it. Skipping used to last one launch, so setup ambushed the user
    /// on every cold start; now it is remembered and the Dashboard banner is
    /// the way back (QA-9).
    private func presentSetupIfNeeded() {
        guard !didCheckSetup else { return }
        didCheckSetup = true
        let settings = UserSettings.current(context: modelContext)
        if !settings.hasCompletedSetup && !SetupSkip.isSkipped {
            showSetup = true
        }
    }

    /// Pick up a pending intervention, unless onboarding or the storage notice
    /// is already in front — a first-run user has nothing to be confronted
    /// with yet.
    private func refreshIntervention() {
        guard !showSetup, storageNotice == nil, intervention == nil else { return }
        intervention = WarningInterventionState.pending
    }
}
