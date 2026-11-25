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
    @State private var addError: String?

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
                    AppsPickRow(selection: $additions)
                } header: {
                    Text("Add")
                }

                // Only what is added in this sheet can be taken back out.
                Section {
                    SitesPickRow(domains: $newDomains, lockedDomains: lockedDomains)
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

    private func add() {
        do {
            try onAdd(additions, newDomains)
            dismiss()
        } catch {
            addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
