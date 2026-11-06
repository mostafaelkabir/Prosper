import SwiftUI
import FamilyControls

/// Adds apps and websites to something that is already locking: a running
/// block or a schedule mid-window (UX-22). It can only add. What is already
/// locked is shown but cannot be touched, so this never loosens a lock.
struct AddToLockView: View {
    @Environment(\.dismiss) private var dismiss

    let lockedSelection: FamilyActivitySelection
    let lockedDomains: [String]
    let until: Date
    /// Applies the additions; throws to keep the sheet open with a reason.
    let onAdd: (FamilyActivitySelection, [String]) throws -> Void

    @State private var additions = FamilyActivitySelection()
    @State private var newDomains: [String] = []
    @State private var domainInput = ""
    @State private var domainError: String?
    @State private var isPickerPresented = false
    @State private var addError: String?
    @FocusState private var domainFieldFocused: Bool

    private var lockedCount: Int {
        lockedSelection.applicationTokens.count + lockedSelection.categoryTokens.count
            + lockedSelection.webDomainTokens.count + lockedDomains.count
    }

    private var addedCount: Int {
        additions.applicationTokens.count + additions.categoryTokens.count
            + additions.webDomainTokens.count + newDomains.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SelectionChips(selection: lockedSelection, typedDomains: lockedDomains, placeholderCount: lockedCount, cap: 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Already locked")
                } footer: {
                    Text("Locked until \(until.formatted(date: .omitted, time: .shortened)). You can add to this, but nothing here can be removed.")
                }

                Section {
                    Button {
                        isPickerPresented = true
                    } label: {
                        Label("Add apps", systemImage: "apps.iphone")
                    }
                    if additions.applicationTokens.count + additions.categoryTokens.count + additions.webDomainTokens.count > 0 {
                        SelectionChips(selection: additions)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text("Apps")
                }

                Section {
                    HStack {
                        TextField("reddit.com", text: $domainInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .focused($domainFieldFocused)
                            .onSubmit(addDomain)
                        Button("Add", action: addDomain)
                            .disabled(domainInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let domainError {
                        Text(domainError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    // Only sites added in this sheet can be taken back out.
                    ForEach(newDomains, id: \.self) { domain in
                        SiteLabel(domain: domain)
                    }
                    .onDelete { newDomains.remove(atOffsets: $0) }
                } header: {
                    Text("Websites")
                }
            }
            .navigationTitle("Add to lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lock these", action: add)
                        .disabled(addedCount == 0)
                }
            }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $additions)
            .alert(
                "Nothing was added",
                isPresented: Binding(get: { addError != nil }, set: { if !$0 { addError = nil } })
            ) {
                Button("OK", role: .cancel) { addError = nil }
            } message: {
                Text(addError ?? "")
            }
        }
    }

    private func addDomain() {
        guard let domain = BlockDomain.normalize(domainInput) else {
            domainError = "Enter a website like reddit.com"
            return
        }
        domainError = nil
        if lockedDomains.contains(domain) {
            domainError = "\(domain) is already locked"
        } else if !newDomains.contains(domain) {
            newDomains.append(domain)
        }
        domainInput = ""
        domainFieldFocused = true
    }

    private func add() {
        do {
            try onAdd(additions, newDomains)
            dismiss()
        } catch {
            addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
