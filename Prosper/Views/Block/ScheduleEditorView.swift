import SwiftUI
import FamilyControls

/// Creates or edits one scheduled lock (E3.6). Only reachable while the
/// schedule is off; the Lock tab refuses to open it mid-window.
///
/// The top of the screen is the schedule drawn across a day, and it redraws
/// as the times and days change (UX-30), so what is being set is seen while
/// it is set. Saving is one button in reach of the thumb. Removing a schedule
/// is the one thing here that makes distraction easier, so it takes a hold.
struct ScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ScheduledLock
    @State private var selection: FamilyActivitySelection
    @State private var start: Date
    @State private var end: Date
    @State private var saveError: String?

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

    private var hasName: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Why this cannot be saved yet, said before the button is pressed
    /// instead of in an alert after it.
    private var problem: String? {
        if !hasName { return "Give the schedule a name." }
        return ScheduledLockService.validate(assembled)?.errorDescription
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                    timesCard
                    daysCard
                    coverCard
                    if !isNew { removeCard }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ProsperColor.ground)
            .navigationTitle(isNew ? "New schedule" : "Edit schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
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

    // MARK: - Preview

    /// The schedule as it will run: its name, its hours across the day, and
    /// one line that says it in words.
    private var previewCard: some View {
        let lock = assembled
        return AuroraHeroCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: lock.symbol)
                        .scaledFont(17, weight: .semibold)
                        .foregroundStyle(ProsperColor.accent)
                        .contentTransition(.symbolEffect(.replace))
                    TextField("Name", text: $draft.name)
                        .scaledFont(20, weight: .semibold)
                        .foregroundStyle(ProsperColor.ink)
                        .submitLabel(.done)
                    Image(systemName: "pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ProsperColor.ink2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Locks at \(ScheduledLock.timeText(minute: lock.startMinute)), unlocks at \(ScheduledLock.timeText(minute: lock.endMinute))")
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(ProsperColor.ink)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary(lock))
                        .scaledFont(13)
                        .foregroundStyle(ProsperColor.ink2)
                        .contentTransition(.opacity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.snappy(duration: 0.25), value: lock.startMinute)
                .animation(.snappy(duration: 0.25), value: lock.endMinute)
                .animation(.snappy(duration: 0.25), value: lock.weekdays)
                DayBand(startMinute: lock.startMinute, endMinute: lock.endMinute, now: .now)
            }
        }
    }

    /// "9h a night · Every day", "8h a day · Weekdays".
    private func summary(_ lock: ScheduledLock) -> String {
        let length = LockLength.text(minutes: lock.spanMinutes)
        let days = lock.weekdays.isEmpty ? "No days yet" : lock.daysText
        return "\(length)\(lock.crossesMidnight ? ", overnight" : "") · \(days)"
    }

    // MARK: - Times

    private var timesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Times").labelCaps()
            DatePicker("Locks at", selection: $start, displayedComponents: .hourAndMinute)
                .scaledFont(16, weight: .medium)
                .foregroundStyle(ProsperColor.ink)
            Divider().overlay(ProsperColor.line)
            DatePicker("Unlocks at", selection: $end, displayedComponents: .hourAndMinute)
                .scaledFont(16, weight: .medium)
                .foregroundStyle(ProsperColor.ink)
            if startsNow {
                note("These times cover now, so this locks as soon as you save, and can't be changed until \(ScheduledLock.timeText(minute: assembled.endMinute)).", color: ProsperColor.ember)
            } else if assembled.crossesMidnight {
                note("Runs overnight, unlocking the next morning. While it is locking, this schedule can't be changed or removed.")
            } else {
                note("While it is locking, this schedule can't be changed or removed.")
            }
        }
        .auroraCard()
    }

    // MARK: - Days

    private static let dayPresets: [(label: String, days: Set<Int>)] = [
        ("Every day", Set(1...7)),
        ("Weekdays", Set(2...6)),
        ("Weekends", [1, 7]),
    ]

    private var daysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days").labelCaps()
            HStack(spacing: 8) {
                ForEach(Self.dayPresets, id: \.label) { preset in
                    let on = draft.weekdays == preset.days
                    Button {
                        draft.weekdays = preset.days
                    } label: {
                        Text(preset.label)
                            .scaledFont(14, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(on ? ProsperColor.onAccent : ProsperColor.ink)
                            .background(on ? ProsperColor.accent : ProsperColor.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                ForEach(ScheduledLock.orderedWeekdays(), id: \.self) { weekday in
                    let on = draft.weekdays.contains(weekday)
                    Button {
                        if on { draft.weekdays.remove(weekday) } else { draft.weekdays.insert(weekday) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                            .scaledFont(15, weight: .semibold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(on ? ProsperColor.onAccent : ProsperColor.ink)
                            .background(on ? ProsperColor.accent : ProsperColor.surface2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            note("The day it locks. An overnight schedule set for Friday runs into Saturday morning.")
        }
        .auroraCard()
        .animation(.snappy(duration: 0.2), value: draft.weekdays)
        .sensoryFeedback(.selection, trigger: draft.weekdays)
    }

    // MARK: - What it covers

    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What to lock").labelCaps()
            AppsPickRow(selection: $selection)
            Divider().overlay(ProsperColor.line)
            SitesPickRow(domains: $draft.domains)
            note("Starts as your block list. Changes here only affect this schedule. Websites are blocked in Safari and other browsers on this iPhone only.")
        }
        .auroraCard()
    }

    // MARK: - Remove

    /// Adding a schedule is one tap and a save. Taking one away is a hold:
    /// the friction sits on the side that loosens.
    private var removeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove").labelCaps()
            note("Without this schedule, nothing locks at these times unless you start it yourself.")
            HoldToLock(
                title: "Hold to remove",
                doneTitle: "Removed",
                symbol: "trash.fill",
                duration: 2.5,
                tint: ProsperColor.ember,
                prominent: false,
                accessibilityHint: "Removes this schedule. It will no longer lock by itself.",
                onComplete: remove
            )
        }
        .auroraCard()
    }

    private func note(_ text: String, color: Color = ProsperColor.ink2) -> some View {
        Text(text)
            .scaledFont(13)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Save

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if startsNow && problem == nil {
                // Saving this locks straight away and cannot be taken back,
                // so it is committed the way every lock is: with a hold.
                HoldToLock(
                    title: "Hold to save and lock now",
                    accessibilityHint: "Saves the schedule and locks straight away. Nothing can end it early.",
                    onComplete: save
                )
            } else {
                Button(isNew ? "Save schedule" : "Save changes", action: save)
                    .buttonStyle(AuroraButtonStyle())
                    .disabled(problem != nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider().overlay(ProsperColor.line) }
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

    private func remove() {
        do {
            try ScheduledLockService.shared.delete(draft)
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
