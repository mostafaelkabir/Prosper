import SwiftUI
import SwiftData

/// The user's scheduled locks: bedtime, work focus and their own (E3.6).
struct ScheduleListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var locks: [ScheduledLock] = []
    @State private var editing: EditTarget?
    /// A schedule mid-window: it can only be added to (UX-22).
    @State private var addingTo: ScheduledLock?
    @State private var errorText: String?

    private struct EditTarget: Identifiable {
        let lock: ScheduledLock
        let isNew: Bool
        var id: UUID { lock.id }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                List {
                    if locks.isEmpty {
                        Section {
                            Text("Lock the same things at the same time every day, like your phone at bedtime or feeds during work.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section {
                            ForEach(locks) { lock in
                                row(lock, now: context.date)
                            }
                        } footer: {
                            Text("While a schedule is locking you can add apps and sites to it, but not remove any, change its times or delete it. That is the point.")
                        }
                    }
                }
            }
            .navigationTitle("Schedules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Bedtime", systemImage: "moon.fill") { add(.bedtime) }
                        Button("Work focus", systemImage: "briefcase.fill") { add(.workFocus) }
                        Button("Custom", systemImage: "clock") { add(.custom) }
                    } label: {
                        Label("Add schedule", systemImage: "plus")
                    }
                    .disabled(locks.count >= ScheduledLockService.maxLocks)
                }
            }
            .sheet(item: $editing) { target in
                ScheduleEditorView(lock: target.lock, isNew: target.isNew) { reload() }
            }
            .sheet(item: $addingTo) { lock in
                AddToLockView(
                    lockedSelection: lock.selection,
                    lockedDomains: lock.domains,
                    until: ScheduledLockService.shared.frozenUntil(lock) ?? .now
                ) { additions, domains in
                    try ScheduledLockService.shared.add(selection: additions, domains: domains, to: lock)
                    reload()
                }
            }
            .alert(
                "Locked right now",
                isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
            ) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .onAppear(perform: reload)
        }
    }

    private func row(_ lock: ScheduledLock, now: Date) -> some View {
        let frozenUntil = ScheduledLockService.shared.frozenUntil(lock, now: now)
        return Button {
            if frozenUntil != nil {
                addingTo = lock
            } else {
                editing = EditTarget(lock: lock, isNew: false)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: frozenUntil == nil ? "clock" : "lock.fill")
                    .foregroundStyle(frozenUntil == nil ? ProsperColor.ink3 : ProsperColor.slate)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lock.name)
                        .font(.headline)
                        .foregroundStyle(ProsperColor.ink)
                    Text("\(lock.timeRangeText) · \(lock.daysText)")
                        .font(.subheadline)
                        .foregroundStyle(ProsperColor.ink3)
                    if let frozenUntil {
                        Text("Locking now · until \(frozenUntil.formatted(date: .omitted, time: .shortened)) · tap to add more")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ProsperColor.slate)
                    }
                }
                Spacer()
            }
        }
        .swipeActions {
            if frozenUntil == nil {
                Button("Delete", role: .destructive) { delete(lock) }
            }
        }
    }

    private func add(_ template: ScheduledLock.Template) {
        let settings = UserSettings.current(context: modelContext)
        let lock = ScheduledLock.make(
            template,
            selectionData: settings.wasteAppSelectionData,
            domains: settings.wasteDomains
        )
        editing = EditTarget(lock: lock, isNew: true)
    }

    private func delete(_ lock: ScheduledLock) {
        do {
            try ScheduledLockService.shared.delete(lock)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        reload()
    }

    private func reload() {
        locks = ScheduledLockService.shared.locks.sorted { $0.startMinute < $1.startMinute }
    }
}

// MARK: - Templates and wording

extension ScheduledLock {
    enum Template {
        case bedtime, workFocus, custom
    }

    /// A new schedule pre-filled with the waste list, which the user then
    /// adjusts for this schedule alone.
    static func make(_ template: Template, selectionData: Data?, domains: [String]) -> ScheduledLock {
        switch template {
        case .bedtime:
            return ScheduledLock(name: "Bedtime", startMinute: 22 * 60, endMinute: 7 * 60,
                                 weekdays: Set(1...7), selectionData: selectionData, domains: domains)
        case .workFocus:
            return ScheduledLock(name: "Work focus", startMinute: 9 * 60, endMinute: 17 * 60,
                                 weekdays: Set(2...6), selectionData: selectionData, domains: domains)
        case .custom:
            return ScheduledLock(name: "Focus", startMinute: 13 * 60, endMinute: 15 * 60,
                                 weekdays: Set(1...7), selectionData: selectionData, domains: domains)
        }
    }

    static func timeText(minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var timeRangeText: String {
        "\(Self.timeText(minute: startMinute)) – \(Self.timeText(minute: endMinute))"
    }

    var daysText: String {
        switch weekdays {
        case Set(1...7): return "Every day"
        case Set(2...6): return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return Self.orderedWeekdays().filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// Weekday numbers in the order the user's calendar shows them.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}
