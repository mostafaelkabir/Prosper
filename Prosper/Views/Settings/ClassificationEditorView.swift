import SwiftUI
import SwiftData
import FamilyControls

/// UX-9 — lets the user classify apps and sites into Productive / Distracting /
/// Intentional rest. "Distracting" is the existing waste list, so warnings,
/// quick-block presets and the migration all keep working. Anything not listed
/// stays Unclassified; nothing becomes productive by subtraction.
struct ClassificationEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var productive = FamilyActivitySelection()
    @State private var distracting = FamilyActivitySelection()
    @State private var rest = FamilyActivitySelection()
    @State private var productiveDomains: [String] = []
    @State private var distractingDomains: [String] = []
    @State private var restDomains: [String] = []
    @State private var inputs: [String] = ["", "", ""] // productive, distracting, rest
    @State private var activePicker: TimeClass?
    @State private var loaded = false

    private let classes: [TimeClass] = [.productive, .distracting, .rest]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell Prosper what each app and site means to you. Anything you don't classify stays Unclassified — nothing is assumed productive.")
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink2)
                }
                ForEach(Array(classes.enumerated()), id: \.offset) { index, c in
                    classSection(c, index: index)
                }
            }
            .navigationTitle("Classify your time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { persist(); dismiss() }
                }
            }
            .familyActivityPicker(
                isPresented: Binding(get: { activePicker != nil }, set: { if !$0 { activePicker = nil } }),
                selection: activeSelectionBinding
            )
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - Section per class

    @ViewBuilder
    private func classSection(_ c: TimeClass, index: Int) -> some View {
        let sel = binding(for: c)
        Section {
            Button {
                activePicker = c
            } label: {
                HStack {
                    Circle().fill(c.color).frame(width: 9, height: 9)
                    Text("Pick \(c.label.lowercased()) apps")
                    Spacer()
                    Text("\(sel.wrappedValue.applicationTokens.count + sel.wrappedValue.categoryTokens.count) selected")
                        .foregroundStyle(ProsperColor.ink2)
                }
            }
            if !sel.wrappedValue.applicationTokens.isEmpty || !sel.wrappedValue.categoryTokens.isEmpty {
                SelectionChips(
                    selection: sel.wrappedValue,
                    placeholderCount: sel.wrappedValue.applicationTokens.count + sel.wrappedValue.categoryTokens.count
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                TextField("reddit.com", text: $inputs[index])
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Add") { addDomain(to: c, index: index) }
                    .disabled(inputs[index].trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(domainsBinding(for: c).wrappedValue, id: \.self) { domain in
                Label(domain, systemImage: "globe")
            }
            .onDelete { offsets in
                domainsBinding(for: c).wrappedValue.remove(atOffsets: offsets)
                persist()
            }
        } header: {
            Text(c.label)
        }
    }

    // MARK: - Bindings

    private var activeSelectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { activePicker.map { binding(for: $0).wrappedValue } ?? FamilyActivitySelection() },
            set: { newValue in
                guard let c = activePicker else { return }
                binding(for: c).wrappedValue = newValue
                persist()
            }
        )
    }

    private func binding(for c: TimeClass) -> Binding<FamilyActivitySelection> {
        switch c {
        case .productive: return $productive
        case .distracting: return $distracting
        case .rest: return $rest
        case .unclassified: return .constant(FamilyActivitySelection())
        }
    }

    private func domainsBinding(for c: TimeClass) -> Binding<[String]> {
        switch c {
        case .productive: return $productiveDomains
        case .distracting: return $distractingDomains
        case .rest: return $restDomains
        case .unclassified: return .constant([])
        }
    }

    // MARK: - Domain add (deduped across classes)

    private func addDomain(to c: TimeClass, index: Int) {
        guard let normalized = BlockDomain.normalize(inputs[index]) else { return }
        // One item, one class: drop it from the other classes first.
        for other in classes where other != c {
            domainsBinding(for: other).wrappedValue.removeAll { $0 == normalized }
        }
        var list = domainsBinding(for: c).wrappedValue
        if !list.contains(normalized) { list.append(normalized) }
        domainsBinding(for: c).wrappedValue = list
        inputs[index] = ""
        persist()
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let s = UserSettings.current(context: modelContext)
        productive = WasteSelectionCodec.decode(s.productiveSelectionData)
        distracting = WasteSelectionCodec.decode(s.wasteAppSelectionData)   // waste == distracting (migration)
        rest = WasteSelectionCodec.decode(s.restSelectionData)
        productiveDomains = s.productiveDomains
        distractingDomains = s.wasteDomains
        restDomains = s.restDomains
    }

    private func persist() {
        let s = UserSettings.current(context: modelContext)
        s.productiveSelectionData = WasteSelectionCodec.encode(productive)
        s.productiveDomains = productiveDomains
        s.restSelectionData = WasteSelectionCodec.encode(rest)
        s.restDomains = restDomains
        // Distracting is the waste list.
        s.wasteAppSelectionData = WasteSelectionCodec.encode(distracting)
        s.wasteAppCount = distracting.applicationTokens.count + distracting.categoryTokens.count
        s.wasteDomains = distractingDomains
        try? modelContext.save()

        WarningService.shared.refreshSchedule(
            enabled: s.warningsEnabled,
            selection: distracting,
            typedDomains: distractingDomains,
            thresholdMinutes: s.wasteWarningThresholdMinutes
        )
    }
}
