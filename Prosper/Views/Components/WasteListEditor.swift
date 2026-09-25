import SwiftUI
import FamilyControls

/// The apps / websites / threshold editor for the user's waste list. Rendered
/// as a set of `Form` `Section`s so it can be embedded in both Settings and the
/// onboarding setup flow. The parent owns the state and persists via `onChange`.
struct WasteListEditor: View {
    @Binding var selection: FamilyActivitySelection
    @Binding var typedDomains: [String]
    @Binding var thresholdMinutes: Double
    /// Called after any edit so the parent can persist and refresh the schedule.
    var onChange: () -> Void

    @State private var domainInput = ""
    @State private var domainError: String?
    @State private var isPickerPresented = false
    /// True while a finger is on the threshold slider. Each 5-minute step used
    /// to persist and reinstall the waste monitor, restarting iOS's count for
    /// the day several times per drag; now only where it lands counts (QA-9).
    @State private var isDraggingThreshold = false
    @FocusState private var domainFieldFocused: Bool

    private var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count
    }

    var body: some View {
        Group {
            appsSection
            websitesSection
            thresholdSection
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onChange(of: selection) { _, _ in onChange() }
        .onChange(of: thresholdMinutes) { _, _ in
            // Keyboard and VoiceOver adjustments have no drag to end, so they
            // still persist straight away.
            if !isDraggingThreshold { onChange() }
        }
    }

    private var appsSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Label("Pick waste apps", systemImage: "hourglass")
                    Spacer()
                    Text("\(selectedCount) selected")
                        .foregroundStyle(.secondary)
                }
            }
            if selectedCount > 0 {
                Button {
                    isPickerPresented = true
                } label: {
                    SelectionChips(selection: selection, placeholderCount: selectedCount)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Waste apps")
        } footer: {
            Text("Apps or Screen Time categories that count as waste on this device. Warnings count time in what you pick here.")
        }
    }

    private var websitesSection: some View {
        Section {
            HStack {
                TextField("reddit.com", text: $domainInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($domainFieldFocused)
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
                onChange()
            }
        } header: {
            Text("Waste websites")
        } footer: {
            Text("Used for blocking: these become the default list when you open the New Block sheet. iOS can't measure time on a typed site, so they don't count toward warnings — pick apps and categories above for that.")
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
                Slider(value: $thresholdMinutes, in: 5...240, step: 5) { editing in
                    isDraggingThreshold = editing
                    if !editing { onChange() }
                }
            }
        } header: {
            Text("Threshold")
        } footer: {
            Text("Combined time across the apps and categories you picked in a single day before StolenEyes warns you, then keeps warning: \(WarningLevel.ladderText(base: Int(thresholdMinutes)))")
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
        domainFieldFocused = true
        onChange()
    }
}
