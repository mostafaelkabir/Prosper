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
    /// The night that has just been won, while its celebration plays: the
    /// count rolls up, the flame catches, and that night's cell is ticked
    /// (UX-30). A "Not today" night never sets this.
    @State private var justWon: Date?
    /// The streak before that night was won, which the count rolls up from.
    @State private var streakBefore = 0

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
        // Only a night that was not already a win is celebrated, so changing
        // an answer back and forth cannot be farmed for confetti.
        let isNewWin = outcome == .won && center.history.outcome(on: day) != .won
        streakBefore = center.history.currentStreak(now: .now)
        justWon = isNewWin ? day : nil
        withAnimation(.easeOut(duration: 0.2)) {
            center.answer(outcome, for: day)
            changingDay = nil
        }
        guard isNewWin else { return }
        // Long enough for the celebration; after that the card is at rest and
        // a redraw must not play it again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if justWon == day { justWon = nil }
        }
    }

    // MARK: - Streak

    private func streak(now: Date, history: CheckInHistory) -> some View {
        let current = history.currentStreak(now: now)
        let today = center.calendar.day(for: now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                StreakTitle(current: current, previous: streakBefore, celebrate: justWon != nil)
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
                    isToday: day == today,
                    isJustWon: day == justWon
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

/// The flame and the streak count. When a night has just been won the count
/// starts one short and rolls up, and the flame catches with a burst of
/// sparks: the win is seen being added, not just found there. The beats
/// follow Duolingo's streak screen
/// (60fps.design/shots/duolingo-185-day-streak-animation), kept small enough
/// to live inside a card.
private struct StreakTitle: View {
    let current: Int
    /// The streak before the night that was just won.
    let previous: Int
    let celebrate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The count on screen; behind `current` until the celebration lands.
    @State private var shown: Int?
    @State private var lit = true
    @State private var sparks = 0

    private var count: Int { shown ?? current }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .foregroundStyle(lit ? ProsperColor.accent : ProsperColor.unclassified)
                .symbolEffect(.bounce, value: sparks)
                .background { SparkBurst(trigger: sparks, radius: 22) }
            Text(count > 0 ? "^[\(count) night](inflect: true) winning streak" : "Winning streak")
                .scaledFont(16, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
                .contentTransition(.numericText(value: Double(count)))
        }
        .sensoryFeedback(.success, trigger: sparks)
        .onAppear {
            guard celebrate, current > 0 else { return }
            if reduceMotion {
                AccessibilityNotification.Announcement(announcement).post()
                return
            }
            // Open on the streak as it was, with the flame out.
            shown = min(previous, current)
            lit = false
            // After the night's cell has been ticked (see WinCell).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                    shown = nil
                    lit = true
                }
                sparks += 1
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
        // The streak can change under a count that is still held back.
        .onChange(of: current) { _, _ in shown = nil }
    }

    private var announcement: String {
        current == 1 ? "Won. 1 night winning streak." : "Won. \(current) nights winning streak."
    }
}

/// Seven nights: won, not today, or unrecorded.
struct WinStrip: View {
    struct Day: Identifiable {
        let label: String
        let outcome: CheckInOutcome?
        let isToday: Bool
        /// Won a moment ago: its cell is ticked in front of the user.
        var isJustWon = false
        var id: String { label }
    }

    let days: [Day]

    var body: some View {
        let celebrating = days.contains(where: \.isJustWon)
        HStack(spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 5) {
                    WinCell(day: day, order: index, wave: celebrating)
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

    private func spoken(_ day: Day) -> String {
        switch day.outcome {
        case .won: "won"
        case .notToday: "not today"
        case nil: day.isToday ? "not answered yet" : "not recorded"
        }
    }
}

/// One night's cell. At rest it only shows its outcome. During a celebration
/// the earlier wins nod in turn, left to right, and the night just won starts
/// as the empty outlined cell it was a second ago, then fills, takes its tick
/// with a spring and lets go of a ripple.
private struct WinCell: View {
    let day: WinStrip.Day
    /// Position in the strip, which sets when it nods.
    let order: Int
    /// A night elsewhere in the strip has just been won.
    let wave: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False only while a just-won cell is still waiting to be ticked.
    @State private var landed = true
    @State private var nodding = false
    /// The ripple is drawn from the moment the tick lands, then let go.
    @State private var rippleOn = false
    @State private var rippled = false

    private var isWon: Bool { day.outcome == .won && landed }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 11, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(isWon ? ProsperColor.accent.opacity(0.22) : ProsperColor.surface2)
            if (day.isToday && day.outcome == nil) || !landed {
                shape.strokeBorder(ProsperColor.accent, lineWidth: 1.5)
            }
            if rippleOn {
                shape
                    .stroke(ProsperColor.accent, lineWidth: 2)
                    .scaleEffect(rippled ? 1.7 : 1)
                    .opacity(rippled ? 0 : 0.8)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.7)) { rippled = true }
                    }
            }
            Text(symbol)
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(isWon ? ProsperColor.accent : ProsperColor.ink2)
                .scaleEffect(day.isJustWon && !landed ? 0.2 : 1)
        }
        .frame(height: 33)
        .scaleEffect(nodding ? 1.12 : 1)
        .onAppear(perform: play)
    }

    private var symbol: String {
        if !landed { return "·" }
        switch day.outcome {
        case .won: return "✓"
        case .notToday: return "–"
        case nil: return "·"
        }
    }

    private func play() {
        guard wave, !reduceMotion else { return }
        if day.isJustWon {
            landed = false
            // After the nod has run along the cells before it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 + 0.06 * Double(order)) {
                withAnimation(.spring(duration: 0.4, bounce: 0.55)) { landed = true }
                rippleOn = true
            }
        } else if day.outcome == .won {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + 0.06 * Double(order)) {
                withAnimation(.spring(duration: 0.18, bounce: 0.3)) { nodding = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(duration: 0.3, bounce: 0.4)) { nodding = false }
                }
            }
        }
    }
}
