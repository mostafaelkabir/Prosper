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
    @State private var requirePhrase = true

    @State private var loaded = false
    @State private var didRequestNotifications = false

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
            }
            .navigationTitle("Settings")
            .onAppear(perform: loadIfNeeded)
            .onChange(of: warningsEnabled) { _, _ in persist() }
            .onChange(of: requirePhrase) { _, _ in persist() }
        }
    }

    // MARK: - Sections

    private var warningsToggleSection: some View {
        Section {
            Toggle("Warn me about waste time", isOn: $warningsEnabled)
        } footer: {
            Text("Prosper watches the apps and sites you list here and pings you when today's total goes past the threshold.")
        }
    }

    private var escalationSection: some View {
        Section {
            Toggle("Type a phrase to dismiss", isOn: $requirePhrase)
        } header: {
            Text("Third warning")
        } footer: {
            Text("At three times your threshold Prosper takes over the screen instead of sending another notification. With this on, you have to type \u{201C}\(InterventionView.phrase)\u{201D} to get past it.")
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
