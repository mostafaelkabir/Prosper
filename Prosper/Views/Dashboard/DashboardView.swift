import SwiftUI
import SwiftData

/// Today — the approved Aurora dashboard (UX-10). This is the Slice-A visual
/// shell: the hero four-class balance, streak and milestone use clearly labelled
/// example fixtures until live classification (UX-9/E2.5b) and streak (UX-13)
/// data are wired. The "Plan a focus block" action is real and opens the block
/// flow. Reference: docs/design/approved-prosper/HANDOFF.md.
struct DashboardView: View {
    var onResumeSetup: () -> Void = {}

    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]
    @Query private var allSettings: [UserSettings]

    enum Range: Hashable { case day, week }
    @State private var range: Range = .day
    @State private var showCreateBlock = false
    @State private var pendingPrefill: BlockPrefill?

    private var settings: UserSettings? { allSettings.first }
    private var activeSession: BlockSession? { sessions.first { $0.isActive } }
    private var hasWasteList: Bool {
        (settings?.wasteAppCount ?? 0) > 0 || !(settings?.wasteDomains.isEmpty ?? true)
    }

    // Canonical preview fixtures from HANDOFF.md (example data).
    private var balance: TimeBalance {
        switch range {
        case .day:  return TimeBalance(productive: 130*60, distracting: 35*60, rest: 30*60, unclassified: 15*60)
        case .week: return TimeBalance(productive: 880*60, distracting: 245*60, rest: 210*60, unclassified: 105*60)
        }
    }

    // MARK: - Real focus streak (UX-13)

    /// Finished focus sessions (ended), newest first.
    private var finishedSessions: [BlockSession] {
        sessions.filter { !$0.isActive }
    }
    private var completedCount: Int { finishedSessions.count }
    private var milestoneTarget: Int { ((completedCount / 10) + 1) * 10 }

    private func dayHasSession(_ day: Date) -> Bool {
        let cal = Calendar.current
        return finishedSessions.contains { cal.isDate($0.startedAt, inSameDayAs: day) }
    }

    /// Consecutive days with a completed session, counting back from today. A
    /// pending (not-yet-completed) today does not break yesterday's streak.
    private var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !dayHasSession(day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while dayHasSession(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// This calendar week's seven cells (locale week-to-date).
    private var weekDays: [StreakDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let week = cal.dateInterval(of: .weekOfYear, for: today) else { return [] }
        return (0..<7).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            let label = d.formatted(.dateTime.weekday(.abbreviated)).uppercased()
            let state: StreakDay.State
            if cal.isDate(d, inSameDayAs: today) {
                state = .current
            } else if d > today {
                state = .upcoming
            } else {
                state = dayHasSession(d) ? .done : .upcoming
            }
            return StreakDay(label: label, state: state)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    brandRow
                    headline

                    AuroraSegmented(
                        options: [(.day, "Today"), (.week, "This week")],
                        selection: $range
                    )

                    if let settings, !settings.hasCompletedSetup {
                        setupCard
                    }

                    heroCard
                    exampleNote

                    if let session = activeSession {
                        activeBlockCard(session)
                    } else {
                        streakSection
                        OpportunityCard(
                            eyebrow: "Make room for what matters",
                            headline: "Protect time for what you value.",
                            evidence: "Choose a focus block to lock your distractions for a set stretch.",
                            onPlan: startPlan
                        )
                        milestoneRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(ProsperColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateBlock) { CreateBlockView() }
            .sheet(item: $pendingPrefill) { CreateBlockView(prefill: $0) }
        }
    }

    // MARK: - Header

    private var brandRow: some View {
        HStack {
            Text("PROSPER")
                .font(.system(size: 12, weight: .semibold))
                .tracking(2)
                .foregroundStyle(ProsperColor.ink)
            Spacer()
            Image(systemName: "sparkles").foregroundStyle(ProsperColor.accent)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your time.")
                .foregroundStyle(ProsperColor.ink)
            Text("More intentional.")
                .foregroundStyle(ProsperColor.accent)
        }
        .font(.system(size: 30, weight: .semibold))
    }

    // MARK: - Hero

    private var heroCard: some View {
        AuroraHeroCard {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Productive time").labelCaps()
                        Text(balance.productive.usageFormatted)
                            .font(.system(size: 38, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(ProsperColor.ink)
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.4), value: balance)
                        Text("Based on your classifications")
                            .font(.system(size: 12))
                            .foregroundStyle(ProsperColor.ink2)
                    }
                    Spacer()
                    TimeRing(balance: balance)
                }
                CategoryBreakdown(balance: balance)
            }
        }
    }

    private var exampleNote: some View {
        Text("Example data — live once you classify your apps.")
            .labelCaps()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Streak / milestone (real, from completed sessions)

    @ViewBuilder
    private var streakSection: some View {
        if completedCount == 0 {
            OpportunityCard(
                eyebrow: "Focus streak",
                headline: "Start your first focus session.",
                evidence: "Complete one focus block a day to build a streak. Nothing here is pre-filled.",
                ctaTitle: "Plan a focus block",
                onPlan: startPlan
            )
        } else {
            StreakStrip(
                title: "\(currentStreak)-day focus streak",
                days: weekDays,
                onGoal: {}
            )
        }
    }

    @ViewBuilder
    private var milestoneRow: some View {
        if completedCount > 0 {
            MilestoneRow(completed: completedCount, target: milestoneTarget)
        }
    }

    // MARK: - Active block

    private func activeBlockCard(_ session: BlockSession) -> some View {
        AuroraHeroCard {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, session.endTime.timeIntervalSince(context.date))
                let progress = session.duration > 0 ? remaining / session.duration : 0
                HStack(spacing: 16) {
                    CountdownRing(progress: progress, centerText: "", caption: nil, size: 56, lineWidth: 5,
                                  emphasize: remaining <= 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Locked").labelCaps()
                        Text(Self.remainingText(remaining))
                            .font(.system(size: 20, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(ProsperColor.ink)
                        Text("until \(session.endTime.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12))
                            .foregroundStyle(ProsperColor.ink2)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        Button(action: onResumeSetup) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish setting up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProsperColor.ink)
                    Text("Pick your waste apps and sites so Prosper can watch for you.")
                        .font(.system(size: 12))
                        .foregroundStyle(ProsperColor.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ProsperColor.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ProsperColor.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startPlan() {
        if hasWasteList, let settings {
            pendingPrefill = QuickPreset.all.first?.prefill(from: settings)
        } else {
            showCreateBlock = true
        }
    }

    private static func remainingText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        return "\(minutes)m left"
    }
}
