import SwiftUI
import SwiftData
import FamilyControls
import UserNotifications

struct SettingsView: View {
    /// Reopens the post-authorization setup flow ("Set up again").
    var onOpenSetup: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Query private var settingsQuery: [UserSettings]

    // Local mirrors of the persisted UserSettings so editing feels responsive
    // and typed domains can be validated before writing back.
    @State private var warningsEnabled = true
    @State private var selection = FamilyActivitySelection()
    @State private var typedDomains: [String] = []
    @State private var thresholdMinutes: Double = 30
    @State private var requirePhrase = false

    /// Read, never assumed: a user who tapped "Not now" in setup or switched
    /// notifications off in iOS Settings gets told warnings can't reach them,
    /// instead of a static line and a surprise prompt (QA-9).
    @State private var notificationStatus: UNAuthorizationStatus?
    /// Why the waste monitor is not running, if iOS refused it (QA-9).
    @State private var scheduleFailure: String?
    @State private var showDeleteConfirmation = false
    @State private var deleteResult: DeleteResult?

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// What the wipe actually did, so the confirmation is specific rather than
    /// a generic "done".
    private struct DeleteResult: Identifiable {
        let keptActiveBlock: Bool
        var id: Bool { keptActiveBlock }
    }

    private var settings: UserSettings {
        UserSettings.current(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                warningsToggleSection
                if warningsEnabled {
                    WasteListEditor(
                        selection: $selection,
                        typedDomains: $typedDomains,
                        thresholdMinutes: $thresholdMinutes,
                        onChange: persistWasteList
                    )
                    escalationSection
                    notificationsSection
                }
                classificationSection
                setupSection
                lockSection
                aboutSection
                dataSection
            }
            .navigationTitle("Settings")
            // Reloaded on every appearance, not once per view lifetime: the
            // waste list is also edited in Classify your time and setup, and
            // a stale copy here used to overwrite it on the next toggle (QA-9).
            .onAppear(perform: load)
            .task { await refreshNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in
                // Coming back from iOS Settings is when the answer changes.
                if phase == .active { Task { await refreshNotificationStatus() } }
            }
            // Each toggle writes only its own field, so it can never carry an
            // old waste list back into the store (QA-9).
            .onChange(of: warningsEnabled) { _, value in
                save { $0.warningsEnabled = value }
            }
            .onChange(of: requirePhrase) { _, value in
                save { $0.level3PhraseRequired = value }
            }
            .confirmationDialog(
                "Delete everything StolenEyes has stored?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete my data", role: .destructive, action: deleteData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your usage history, warnings, block history, lists and settings are erased from this iPhone. This cannot be undone. A block that is still running keeps running — deleting data is not a way to end one.")
            }
            .alert(item: $deleteResult) { result in
                Alert(
                    title: Text("Data deleted"),
                    message: Text(result.keptActiveBlock
                        ? "Everything stored on this iPhone is gone. Your running block is untouched and still ends at its own time."
                        : "Everything StolenEyes had stored on this iPhone is gone."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Sections

    private var warningsToggleSection: some View {
        Section {
            Toggle("Warn me about waste time", isOn: $warningsEnabled)
            if warningsEnabled, let scheduleFailure {
                Label(scheduleFailure, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("StolenEyes watches the apps and categories you pick below and pings you when today's total goes past the threshold.")
        }
    }

    private var escalationSection: some View {
        Section {
            Toggle("Type a phrase to dismiss", isOn: $requirePhrase)
        } header: {
            Text("Third warning")
        } footer: {
            Text("At three times your threshold StolenEyes takes over the screen instead of sending another notification. With this on, \u{201C}Keep going anyway\u{201D} only lights up once you have typed \u{201C}\(InterventionView.phrase)\u{201D}. You can always close the screen either way — the friction is a choice, not a lock.")
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            switch notificationStatus {
            case .denied:
                Label("Notifications are off — warnings can't reach you", systemImage: "bell.slash.fill")
                    .foregroundStyle(.orange)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
            case .notDetermined:
                Label("Warnings arrive as notifications, which aren't on yet.", systemImage: "bell")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Turn on notifications") {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        await refreshNotificationStatus()
                    }
                }
            case nil:
                EmptyView()
            default:
                Label("Warnings arrive as notifications.", systemImage: "bell.badge")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications")
        }
    }

    private var classificationSection: some View {
        Section {
            NavigationLink {
                ClassificationEditorView()
            } label: {
                Label("Classify your time", systemImage: "circle.grid.2x2")
            }
        } header: {
            Text("Time classes")
        } footer: {
            Text("Mark apps and sites as Productive, Distracting or Intentional rest. Your waste list counts as Distracting; the rest stays Unclassified until you decide.")
        }
    }

    private var setupSection: some View {
        Section {
            Button {
                onOpenSetup()
            } label: {
                Label("Set up again", systemImage: "sparkles")
            }
        } footer: {
            Text("Walk through picking waste apps, sites, and notifications again.")
        }
    }

    /// REL-8: the exit is documented where a user will actually meet it, not
    /// only in the App Store description.
    private var lockSection: some View {
        Section {
            Text(LockExitCopy.full)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("How a block ends")
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                openURL(AppInfo.supportURL)
            } label: {
                Label("Support and feedback", systemImage: "questionmark.circle")
            }
            Button {
                openURL(AppInfo.privacyPolicyURL)
            } label: {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            LabeledContent("Version", value: AppInfo.versionString)
                .foregroundStyle(.secondary)
        } header: {
            Text("About")
        } footer: {
            Text("StolenEyes has no account and no server. Nothing you do here leaves this iPhone.")
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete my data", systemImage: "trash")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Erases everything stored on this iPhone. A running block is not affected — it still ends at its own time.")
        }
    }

    private func deleteData() {
        let outcome = DataReset.deleteEverything(context: modelContext)
        // Re-read the freshly created defaults so the form is not showing
        // values that no longer exist.
        load()
        deleteResult = DeleteResult(keptActiveBlock: outcome.keptActiveBlock)
    }

    // MARK: - Persistence

    /// No notification prompt here any more: opening a tab is not consent, and
    /// it re-prompted users who had already said "Not now" (QA-9).
    private func load() {
        let s = settings
        warningsEnabled = s.warningsEnabled
        selection = WasteSelectionCodec.decode(s.wasteAppSelectionData)
        typedDomains = s.wasteDomains
        thresholdMinutes = Double(max(5, s.wasteWarningThresholdMinutes))
        requirePhrase = s.level3PhraseRequired
        scheduleFailure = WarningService.shared.lastFailure
    }

    /// Called by the waste list editor: the list and threshold are the only
    /// fields it edits, so they are the only ones written.
    private func persistWasteList() {
        save { s in
            s.wasteAppSelectionData = WasteSelectionCodec.encode(selection)
            s.wasteAppCount = selection.applicationTokens.count + selection.categoryTokens.count
            s.wasteDomains = typedDomains
            s.wasteWarningThresholdMinutes = Int(thresholdMinutes)
        }
    }

    /// Applies one change to the stored settings, then reschedules warnings
    /// from what is stored — never from this view's copies of other fields.
    private func save(_ change: (UserSettings) -> Void) {
        let s = settings
        change(s)
        try? modelContext.save()
        s.syncClassificationSnapshot()

        WarningService.shared.refreshSchedule(
            enabled: s.warningsEnabled,
            selection: WasteSelectionCodec.decode(s.wasteAppSelectionData),
            typedDomains: s.wasteDomains,
            thresholdMinutes: s.wasteWarningThresholdMinutes
        )
        scheduleFailure = WarningService.shared.lastFailure
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.authorizationStatus()
    }
}
