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

    private let streakDays: [StreakDay] = [
        .init(label: "MON", state: .done), .init(label: "TUE", state: .done),
        .init(label: "WED", state: .done), .init(label: "THU", state: .done),
        .init(label: "FRI", state: .done), .init(label: "SAT", state: .current),
        .init(label: "SUN", state: .upcoming)
    ]

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

    // MARK: - Streak / milestone (example fixtures)

    private var streakSection: some View {
        StreakStrip(title: "6-day focus streak", days: streakDays, onGoal: {})
    }

    private var milestoneRow: some View {
        MilestoneRow(completed: 9, target: 10)
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
