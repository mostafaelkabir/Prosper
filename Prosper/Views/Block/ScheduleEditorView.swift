import SwiftUI
import FamilyControls

/// Creates or edits one scheduled lock (E3.6). Only reachable while the
/// schedule is off; the list refuses to open it mid-window.
struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduledLock
    @State private var selection: FamilyActivitySelection
    @State private var start: Date
    @State private var end: Date
    @State private var domainInput = ""
    @State private var domainError: String?
    @State private var isPickerPresented = false
    @State private var saveError: String?
    @FocusState private var domainFieldFocused: Bool

    let isNew: Bool
    let onSaved: () -> Void

    init(lock: ScheduledLock, isNew: Bool, onSaved: @escaping () -> Void) {
        _draft = State(initialValue: lock)
        _selection = State(initialValue: lock.selection)
        _start = State(initialValue: Self.date(minute: lock.startMinute))
        _end = State(initialValue: Self.date(minute: lock.endMinute))
        self.isNew = isNew
        self.onSaved = onSaved
    }

    private var assembled: ScheduledLock {
        var lock = draft
        lock.startMinute = Self.minute(of: start)
        lock.endMinute = Self.minute(of: end)
        lock.selectionData = try? JSONEncoder().encode(selection)
        return lock
    }

    /// True when saving would lock straight away because the new times
    /// already cover now.
    private var startsNow: Bool { assembled.window(containing: .now) != nil }

    private var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }
                timesSection
                daysSection
                appsSection
                websitesSection
            }
            .navigationTitle(isNew ? "New schedule" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .alert(
                "Not saved",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var timesSection: some View {
        Section {
            DatePicker("Locks at", selection: $start, displayedComponents: .hourAndMinute)
            DatePicker("Unlocks at", selection: $end, displayedComponents: .hourAndMinute)
        } footer: {
            let lock = assembled
            if startsNow {
                Text("These times cover now, so this locks as soon as you save, and can't be changed until \(ScheduledLock.timeText(minute: lock.endMinute)).")
                    .foregroundStyle(ProsperColor.ember)
            } else if lock.crossesMidnight {
                Text("Runs overnight, unlocking the next morning. While it is locking, this schedule can't be changed or removed.")
            } else {
                Text("While it is locking, this schedule can't be changed or removed.")
            }
        }
    }

    private var daysSection: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(ScheduledLock.orderedWeekdays(), id: \.self) { weekday in
                    let on = draft.weekdays.contains(weekday)
                    Button {
                        if on { draft.weekdays.remove(weekday) } else { draft.weekdays.insert(weekday) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? Color.white : ProsperColor.ink)
                            .background(on ? ProsperColor.slate : ProsperColor.card2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        } header: {
            Text("Days")
        } footer: {
            Text("The day it locks. An overnight schedule set for Friday runs into Saturday morning.")
        }
    }

    private var appsSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Label("Select Apps", systemImage: "apps.iphone")
                    Spacer()
                    Text("\(selectedCount) selected").foregroundStyle(.secondary)
                }
            }
            if selectedCount > 0 {
                SelectionChips(selection: selection, placeholderCount: selectedCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Apps")
        } footer: {
            Text("Starts as your waste list. Changes here only affect this schedule.")
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
                    .onSubmit(addDomain)
                Button("Add", action: addDomain)
                    .disabled(domainInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let domainError {
                Text(domainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(draft.domains, id: \.self) { domain in
                SiteLabel(domain: domain)
            }
            .onDelete { draft.domains.remove(atOffsets: $0) }
        } header: {
            Text("Websites")
        } footer: {
            Text("Blocked in Safari and other browsers on this iPhone only.")
        }
    }

    private func addDomain() {
        guard let domain = BlockDomain.normalize(domainInput) else {
            domainError = "Enter a website like reddit.com"
            return
        }
        domainError = nil
        if !draft.domains.contains(domain) { draft.domains.append(domain) }
        domainInput = ""
        domainFieldFocused = true
    }

    private func save() {
        var lock = assembled
        lock.name = lock.name.trimmingCharacters(in: .whitespaces)
        do {
            try ScheduledLockService.shared.save(lock)
            onSaved()
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func date(minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
