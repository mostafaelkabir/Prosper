import SwiftUI

/// The nightly check-in on Today (E10.1). In the evening it asks the question
/// with two buttons; the rest of the time it shows the winning streak and the
/// last seven nights.
///
/// Never shaming: a "Not today" night is a quiet dash, not a red cell, and the
/// line under the streak always has the best streak and total wins in it, so a
/// lapse never wipes what is on screen.
struct NightlyCheckInCard: View {
    @ObservedObject private var center = NightlyCheckInCenter.shared
    /// Reopens tonight's question after it was answered, to fix a mis-tap.
    @State private var changingDay: Date?

    var body: some View {
        // Re-evaluated each minute so the question appears at 6 PM on its own.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ProsperColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(ProsperColor.line, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let history = center.history
        // A missed night waits here until it is answered, newest first.
        let waiting = history.unansweredDays(now: now, reminderMinute: center.reminderMinute, since: center.since)
        if let day = changingDay ?? waiting.first {
            question(for: day, now: now, history: history, waitingAfter: changingDay == nil ? waiting.count - 1 : 0)
        } else {
            streak(now: now, history: history)
        }
    }

    // MARK: - Asking

    private func question(for day: Date, now: Date, history: CheckInHistory, waitingAfter: Int) -> some View {
        let today = center.calendar.day(for: now)
        let isTonight = day == today
        let when = Self.when(day, today: today, calendar: center.calendar.calendar)
        let streak = history.currentStreak(now: now)
        return VStack(alignment: .leading, spacing: 10) {
            Text(isTonight ? "Before you sleep" : "Still waiting for your answer").labelCaps()
            Text(center.prompt.question(when: when))
                .scaledFont(18, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if streak > 0 {
                Text("^[\(streak) night](inflect: true) in a row so far.")
                    .scaledFont(12)
                    .foregroundStyle(ProsperColor.ink2)
            }
            HStack(spacing: 10) {
                answerButton("I won", systemImage: "checkmark", filled: true) {
                    answer(.won, day: day)
                }
                answerButton(isTonight ? "Not today" : "Not that day", systemImage: "minus", filled: false) {
                    answer(.notToday, day: day)
                }
            }
            .padding(.top, 4)
            if waitingAfter > 0 {
                Text("^[\(waitingAfter) more night](inflect: true) waiting after this one.")
                    .scaledFont(12)
                    .foregroundStyle(ProsperColor.ink2)
            }
        }
    }

    /// "today", "yesterday", "on Monday" within the week, else "on Nov 3".
    private static func when(_ day: Date, today: Date, calendar: Calendar) -> String {
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch daysAgo {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...6: return "on " + day.formatted(.dateTime.weekday(.wide))
        default: return "on " + day.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func answerButton(_ title: String, systemImage: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .scaledFont(15, weight: .semibold)
                .frame(maxWidth: .infinity, minHeight: 45)
                .foregroundStyle(filled ? ProsperColor.onAccent : ProsperColor.ink)
                .background(filled ? ProsperColor.accent : ProsperColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func answer(_ outcome: CheckInOutcome, day: Date) {
        withAnimation(.easeOut(duration: 0.2)) {
            center.answer(outcome, for: day)
            changingDay = nil
        }
    }

    // MARK: - Streak

    private func streak(now: Date, history: CheckInHistory) -> some View {
        let current = history.currentStreak(now: now)
        let today = center.calendar.day(for: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "flame.fill").foregroundStyle(ProsperColor.accent)
                    Text(current > 0 ? "^[\(current) night](inflect: true) winning streak" : "Winning streak")
                        .scaledFont(16, weight: .semibold)
                        .foregroundStyle(ProsperColor.ink)
                }
                Spacer()
                if history.outcome(on: today) != nil {
                    Button("Change") { changingDay = today }
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.accent)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Change tonight's answer")
                }
            }
            WinStrip(days: history.lastSevenDays(now: now).map { day in
                WinStrip.Day(
                    label: day.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
                    outcome: history.outcome(on: day),
                    isToday: day == today
                )
            })
            Text(footnote(now: now, today: today, history: history))
                .scaledFont(12)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footnote(now: Date, today: Date, history: CheckInHistory) -> String {
        let record = "Best streak: \(Self.nights(history.bestStreak)). Won so far: \(Self.nights(history.totalWins))."
        switch history.outcome(on: today) {
        case .won:
            return "Won today. Sleep well. \(record)"
        case .notToday:
            return "Noted. One day doesn't undo the others; tomorrow is a fresh start. \(record)"
        case nil:
            let opens = center.calendar.opensAt(today, reminderMinute: center.reminderMinute)
            let time = (opens ?? now).formatted(date: .omitted, time: .shortened)
            return history.totalWins == 0
                ? "You'll be asked tonight from \(time). One honest answer a night."
                : "Check in tonight from \(time). \(record)"
        }
    }

    private static func nights(_ count: Int) -> String {
        count == 1 ? "1 night" : "\(count) nights"
    }
}

/// Seven nights: won, not today, or unrecorded.
struct WinStrip: View {
    struct Day: Identifiable {
        let label: String
        let outcome: CheckInOutcome?
        let isToday: Bool
        var id: String { label }
    }

    let days: [Day]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(day.outcome == .won ? ProsperColor.accent.opacity(0.22) : ProsperColor.surface2)
                        if day.isToday && day.outcome == nil {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(ProsperColor.accent, lineWidth: 1.5)
                        }
                        Text(symbol(day.outcome))
                            .scaledFont(14, weight: .semibold)
                            .foregroundStyle(day.outcome == .won ? ProsperColor.accent : ProsperColor.ink2)
                    }
                    .frame(height: 33)
                    Text(day.label)
                        .scaledFont(10)
                        .foregroundStyle(ProsperColor.ink2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.label): \(spoken(day))")
            }
        }
    }

    private func symbol(_ outcome: CheckInOutcome?) -> String {
        switch outcome {
        case .won: "✓"
        case .notToday: "–"
        case nil: "·"
        }
    }

    private func spoken(_ day: Day) -> String {
        switch day.outcome {
        case .won: "won"
        case .notToday: "not today"
        case nil: day.isToday ? "not answered yet" : "not recorded"
        }
    }
}
