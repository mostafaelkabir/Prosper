import SwiftUI
import SwiftData

/// The user's scheduled locks, on the Lock tab itself (E3.6, UX-30).
///
/// A schedule is the strongest habit the app offers: set once, it locks by
/// itself every time, with no decision left to make at 10 PM. It used to sit
/// behind a small calendar button and an empty list. Now it is a card under
/// the block list. With no schedule yet, the two that most people want are
/// one tap away, already filled with the block list; with some, each shows its
/// hours as a bar across the day and when it locks next.
struct SchedulesCard: View {
    /// Called after a schedule is saved, removed or added to, so the screen
    /// around the card can show a lock that has just started.
    var onChange: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var locks: [ScheduledLock] = []
    @State private var editing: EditTarget?
    /// A schedule mid-window: it can only be added to (UX-22).
    @State private var addingTo: ScheduledLock?
    @State private var appeared = false

    private struct EditTarget: Identifiable {
        let lock: ScheduledLock
        let isNew: Bool
        var id: UUID { lock.id }
    }

    private var isFull: Bool { locks.count >= ScheduledLockService.maxLocks }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if locks.isEmpty {
                templates
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 14) {
                        ForEach(Array(locks.enumerated()), id: \.element.id) { index, lock in
                            if index > 0 { Divider().overlay(ProsperColor.line) }
                            row(lock, now: context.date)
                        }
                    }
                }
                Text("While a schedule is locking you can add to it, but not remove anything, change its times or remove it. That is the point.")
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .auroraCard()
        .onAppear {
            reload()
            appeared = true
        }
        .sheet(item: $editing) { target in
            ScheduleEditorView(lock: target.lock, isNew: target.isNew) { changed() }
        }
        .sheet(item: $addingTo) { lock in
            AddToLockView(
                lockedSelection: lock.selection,
                lockedDomains: lock.domains,
                until: ScheduledLockService.shared.frozenUntil(lock) ?? .now
            ) { additions, domains in
                try ScheduledLockService.shared.add(selection: additions, domains: domains, to: lock)
                changed()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Schedules").labelCaps()
                Text(locks.isEmpty
                    ? "Set it once. It locks by itself, on time, every time."
                    : "These lock by themselves. Nothing to remember.")
                    .scaledFont(14)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !locks.isEmpty {
                Menu {
                    Button("Bedtime", systemImage: "moon.fill") { add(.bedtime) }
                    Button("Work focus", systemImage: "briefcase.fill") { add(.workFocus) }
                    Button("Your own times", systemImage: "clock") { add(.custom) }
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .scaledFont(14, weight: .semibold)
                        .foregroundStyle(ProsperColor.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(ProsperColor.accent.opacity(0.14))
                        .clipShape(Capsule())
                }
                .disabled(isFull)
                .opacity(isFull ? 0.4 : 1)
                .accessibilityLabel("Add schedule")
            }
        }
    }

    // MARK: - No schedule yet

    /// The two schedules worth having, drawn as what they will do. A tap
    /// opens one ready to save.
    private var templates: some View {
        VStack(spacing: 10) {
            // Side by side; one above the other when the text is too large.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                templateTile(.bedtime, symbol: "moon.fill", order: 0)
                templateTile(.workFocus, symbol: "briefcase.fill", order: 1)
            }
            Button {
                add(.custom)
            } label: {
                Label("Your own times", systemImage: "plus")
            }
            .buttonStyle(AuroraButtonStyle(quiet: true))
            .modifier(Rise(shown: appeared, order: 2, reduceMotion: reduceMotion))
        }
    }

    private func templateTile(_ template: ScheduledLock.Template, symbol: String, order: Int) -> some View {
        let sample = ScheduledLock.make(template, selectionData: nil, domains: [])
        return Button {
            add(template)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .scaledFont(16, weight: .semibold)
                        .foregroundStyle(ProsperColor.accent)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .scaledFont(18)
                        .foregroundStyle(ProsperColor.accent)
                }
                .padding(.bottom, 2)
                Text(sample.name)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(ProsperColor.ink)
                Text(sample.timeRangeText)
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sample.daysText)
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                DayBand(startMinute: sample.startMinute, endMinute: sample.endMinute, height: 6, showsHours: false)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProsperColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add \(sample.name) schedule, \(sample.timeRangeText), \(sample.daysText)")
        .accessibilityAddTraits(.isButton)
        .modifier(Rise(shown: appeared, order: order, reduceMotion: reduceMotion))
    }

    // MARK: - Rows

    private func row(_ lock: ScheduledLock, now: Date) -> some View {
        let frozenUntil = ScheduledLockService.shared.frozenUntil(lock, now: now)
        return Button {
            if frozenUntil != nil {
                addingTo = lock
            } else {
                editing = EditTarget(lock: lock, isNew: false)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(frozenUntil == nil ? ProsperColor.accent.opacity(0.14) : ProsperColor.accent)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: frozenUntil == nil ? lock.symbol : "lock.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(frozenUntil == nil ? ProsperColor.accent : ProsperColor.onAccent)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lock.name)
                            .scaledFont(16, weight: .semibold)
                            .foregroundStyle(ProsperColor.ink)
                        Text("\(lock.timeRangeText) · \(lock.daysText)")
                            .scaledFont(13)
                            .foregroundStyle(ProsperColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: frozenUntil == nil ? "chevron.right" : "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ProsperColor.accent)
                }
                DayBand(startMinute: lock.startMinute, endMinute: lock.endMinute, now: now, height: 6, showsHours: false)
                if let frozenUntil {
                    Text("Locking now, until \(frozenUntil.formatted(date: .omitted, time: .shortened)). Tap to add more.")
                        .scaledFont(12, weight: .semibold)
                        .foregroundStyle(ProsperColor.accent)
                } else if let next = lock.nextStart(after: now) {
                    Text("Locks next \(ScheduledLock.whenText(next, now: now))")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func add(_ template: ScheduledLock.Template) {
        let settings = UserSettings.current(context: modelContext)
        let lock = ScheduledLock.make(
            template,
            selectionData: settings.wasteAppSelectionData,
            domains: settings.wasteDomains
        )
        editing = EditTarget(lock: lock, isNew: true)
    }

    private func changed() {
        reload()
        onChange()
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

    /// Moon for a lock that runs through the night, clock for a daytime one.
    var symbol: String {
        crossesMidnight || startMinute >= 20 * 60 ? "moon.fill" : "clock.fill"
    }

    /// The next time a window opens after `date`, looking a week ahead.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
                  start > date else { continue }
            return start
        }
        return nil
    }

    /// "today at 10:00 PM", "tomorrow at 9:00 AM", "Monday at 9:00 AM".
    static func whenText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
    }
}
