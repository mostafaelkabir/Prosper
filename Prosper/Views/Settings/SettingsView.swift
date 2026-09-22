import SwiftUI
import SwiftData
import FamilyControls

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

    @State private var loaded = false
    @State private var didRequestNotifications = false
    @State private var showDeleteConfirmation = false
    @State private var deleteResult: DeleteResult?

    @Environment(\.openURL) private var openURL

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
                        onChange: persist
                    )
                    escalationSection
                    infoSection
                }
                classificationSection
                setupSection
                lockSection
                aboutSection
                dataSection
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadIfNeeded)
            .onChange(of: warningsEnabled) { _, _ in persist() }
            .onChange(of: requirePhrase) { _, _ in persist() }
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
        } footer: {
            Text("StolenEyes watches the apps and sites you list here and pings you when today's total goes past the threshold.")
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

    private var infoSection: some View {
        Section {
            Label("Warnings arrive as a local notification. Turn them on in iOS Settings if you did not accept the prompt.",
                  systemImage: "bell.badge")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        loaded = false
        loadIfNeeded()
        deleteResult = DeleteResult(keptActiveBlock: outcome.keptActiveBlock)
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let s = settings
        warningsEnabled = s.warningsEnabled
        selection = WasteSelectionCodec.decode(s.wasteAppSelectionData)
        typedDomains = s.wasteDomains
        thresholdMinutes = Double(max(5, s.wasteWarningThresholdMinutes))
        requirePhrase = s.level3PhraseRequired

        if !didRequestNotifications && warningsEnabled {
            didRequestNotifications = true
            Task { _ = await NotificationService.shared.requestPermission() }
        }
    }

    private func persist() {
        let s = settings
        s.warningsEnabled = warningsEnabled
        s.wasteAppSelectionData = WasteSelectionCodec.encode(selection)
        s.wasteAppCount = selection.applicationTokens.count + selection.categoryTokens.count
        s.wasteDomains = typedDomains
        s.wasteWarningThresholdMinutes = Int(thresholdMinutes)
        s.level3PhraseRequired = requirePhrase
        try? modelContext.save()
        s.syncClassificationSnapshot()

        WarningService.shared.refreshSchedule(
            enabled: warningsEnabled,
            selection: selection,
            typedDomains: typedDomains,
            thresholdMinutes: Int(thresholdMinutes)
        )
    }
}
