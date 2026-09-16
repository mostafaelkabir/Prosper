import SwiftUI
import SwiftData
import FamilyControls

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsQuery: [UserSettings]

    // Local mirrors of the persisted UserSettings so editing feels responsive
    // and typed domains can be validated before writing back.
    @State private var warningsEnabled = true
    @State private var selection = FamilyActivitySelection()
    @State private var typedDomains: [String] = []
    @State private var domainInput = ""
    @State private var domainError: String?
    @State private var thresholdMinutes: Double = 30

    @State private var isPickerPresented = false
    @State private var didRequestNotifications = false
    @State private var loaded = false

    private var settings: UserSettings {
        UserSettings.current(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                warningsToggleSection
                if warningsEnabled {
                    wasteAppsSection
                    wasteWebsitesSection
                    thresholdSection
                    infoSection
                }
            }
            .navigationTitle("Settings")
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onAppear(perform: loadIfNeeded)
            .onChange(of: warningsEnabled) { _, _ in persist() }
            .onChange(of: selection) { _, _ in persist() }
            .onChange(of: thresholdMinutes) { _, _ in persist() }
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

    private var wasteAppsSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Label("Pick waste apps", systemImage: "hourglass")
                    Spacer()
                    Text("\(selection.applicationTokens.count + selection.categoryTokens.count) selected")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Waste apps")
        } footer: {
            Text("Apps or Screen Time categories that count as waste on this device.")
        }
    }

    private var wasteWebsitesSection: some View {
        Section {
            HStack {
                TextField("reddit.com", text: $domainInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .onSubmit(addTypedDomain)
                Button("Add", action: addTypedDomain)
                    .disabled(domainInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let domainError {
                Text(domainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(typedDomains, id: \.self) { domain in
                Label(domain, systemImage: "globe")
            }
            .onDelete { offsets in
                typedDomains.remove(atOffsets: offsets)
                persist()
            }
        } header: {
            Text("Waste websites")
        } footer: {
            Text("These are used both for warnings and as the default list when you open the New Block sheet.")
        }
    }

    private var thresholdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Warn after")
                    Spacer()
                    Text("\(Int(thresholdMinutes)) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $thresholdMinutes, in: 5...240, step: 5)
            }
        } header: {
            Text("Threshold")
        } footer: {
            Text("Combined time across your waste apps and sites in a single day before Prosper warns you.")
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

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let s = settings
        warningsEnabled = s.warningsEnabled
        selection = WasteSelectionCodec.decode(s.wasteAppSelectionData)
        typedDomains = s.wasteDomains
        thresholdMinutes = Double(max(5, s.wasteWarningThresholdMinutes))

        if !didRequestNotifications && warningsEnabled {
            didRequestNotifications = true
            Task { _ = await NotificationService.shared.requestPermission() }
        }
    }

    private func addTypedDomain() {
        guard let normalized = BlockDomain.normalize(domainInput) else {
            domainError = "Enter a website like reddit.com"
            return
        }
        domainError = nil
        if !typedDomains.contains(normalized) {
            typedDomains.append(normalized)
        }
        domainInput = ""
        persist()
    }

    private func persist() {
        let s = settings
        s.warningsEnabled = warningsEnabled
        s.wasteAppSelectionData = WasteSelectionCodec.encode(selection)
        s.wasteAppCount = selection.applicationTokens.count + selection.categoryTokens.count
        s.wasteDomains = typedDomains
        s.wasteWarningThresholdMinutes = Int(thresholdMinutes)
        try? modelContext.save()

        WarningService.shared.refreshSchedule(
            enabled: warningsEnabled,
            selection: selection,
            typedDomains: typedDomains,
            thresholdMinutes: Int(thresholdMinutes)
        )
    }
}
