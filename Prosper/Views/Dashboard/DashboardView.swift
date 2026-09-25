import SwiftUI
import SwiftData
import DeviceActivity

/// Today — the approved Aurora dashboard (UX-10). The hero four-class balance is
/// now live: the ProsperReport extension classifies real Screen Time by the
/// user's labels (UX-9/E2.5b) and renders it via `DeviceActivityReport`. Streak
/// and milestone are real (UX-13). The "Plan a focus block" action opens the
/// block flow. Reference: docs/design/approved-prosper/HANDOFF.md.
struct DashboardView: View {
    var onResumeSetup: () -> Void = {}

    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]
    @Query private var allSettings: [UserSettings]

    enum Range: Hashable { case day, week }
    @State private var range: Range = .day
    @State private var showCreateBlock = false
    @State private var showClassify = false
    @State private var pendingPrefill: BlockPrefill?
    /// Start of the day the report filters were built for; see `ReportDayTracker`.
    @State private var reportDay = Calendar.current.startOfDay(for: .now)

    private var settings: UserSettings? { allSettings.first }
    private var activeSession: BlockSession? { sessions.first { $0.isActive } }
    private var hasWasteList: Bool {
        (settings?.wasteAppCount ?? 0) > 0 || !(settings?.wasteDomains.isEmpty ?? true)
    }

    /// Whether the user has labelled anything in any of the three classes. Drives
    /// the "classify your apps" nudge — without labels the hero is all
    /// Unclassified, and this is the honest fix (not fake data).
    private var hasAnyClassification: Bool {
        guard let s = settings else { return false }
        return (s.wasteAppCount > 0)
            || !s.wasteDomains.isEmpty
            || s.productiveSelectionData != nil || !s.productiveDomains.isEmpty
            || s.restSelectionData != nil || !s.restDomains.isEmpty
    }

    /// Filter for the selected range, passed to the live `DeviceActivityReport`.
    private var balanceFilter: DeviceActivityFilter {
        range == .day ? UsageReportFilter.today() : UsageReportFilter.lastSevenDays()
    }

    /// A fingerprint of the current four-class labels. The `.todayBalance` report
    /// is rendered by the ProsperReport extension in a separate process and iOS
    /// caches it by `(context, filter)` — `SharedClassification.load()` only runs
    /// inside `makeConfiguration`, which the system will not call again while the
    /// context and filter are unchanged. So after the user tags a site or app the
    /// hero would keep showing the stale, pre-classification split. Folding this
    /// signature into the report's `.id` re-embeds it on any label change, forcing
    /// a fresh `makeConfiguration` that re-reads the snapshot. Derived from the
    /// SwiftData `settings` (updated by the editor via @Query), so it changes
    /// whether the labels were edited from Settings or the Today "Classify" sheet.
    private var classificationSignature: Int {
        guard let s = settings else { return 0 }
        var hasher = Hasher()
        hasher.combine(s.wasteAppSelectionData)   // distracting apps
        hasher.combine(s.wasteDomains)            // distracting sites
        hasher.combine(s.productiveSelectionData)
        hasher.combine(s.productiveDomains)
        hasher.combine(s.restSelectionData)
        hasher.combine(s.restDomains)
        return hasher.finalize()
    }

    /// The report day as an id component.
    private var dayKey: Int { Int(reportDay.timeIntervalSince1970) }

    // MARK: - Real focus streak (UX-13)

    /// Genuine focus sessions only — completed *and* at least the meaningful
    /// minimum (UX-21). A short trial block never counts toward the streak or the
    /// milestone, so both mean something and the numbers are true.
    private var focusSessions: [BlockSession] {
        sessions.filter { $0.countsAsFocus }
    }
    private var completedCount: Int { focusSessions.count }
    private var milestoneTarget: Int { ((completedCount / 10) + 1) * 10 }

    private func dayHasSession(_ day: Date) -> Bool {
        let cal = Calendar.current
        return focusSessions.contains { cal.isDate($0.startedAt, inSameDayAs: day) }
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
                    if !hasAnyClassification { classifyCTA }

                    insightSpotlight

                    if let session = activeSession {
                        activeBlockCard(session)
                    } else {
                        streakSection
                        // Only when a streak already exists: the empty-state streak
                        // card already carries a "Plan a focus block" CTA, so showing
                        // this second identical CTA would duplicate it (QA-2).
                        if completedCount > 0 {
                            OpportunityCard(
                                eyebrow: "Make room for what matters",
                                headline: "Protect time for what you value.",
                                evidence: "Choose a focus block to lock your distractions for a set stretch.",
                                onPlan: startPlan
                            )
                        }
                        milestoneRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(ProsperColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .tracksReportDay($reportDay)
            .sheet(isPresented: $showCreateBlock) { CreateBlockView() }
            .sheet(isPresented: $showClassify) { NavigationStack { ClassificationEditorView() } }
            .sheet(item: $pendingPrefill) { CreateBlockView(prefill: $0) }
        }
    }

    // MARK: - Header

    private var brandRow: some View {
        HStack {
            // The shipping name, as on the home screen and in the store.
            // "Prosper" is only the project/repo name (QA-9, REL-14).
            Text("STOLENEYES")
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

    /// Live balance: the report extension classifies real Screen Time and renders
    /// the waste-first hero (`TodayHeroReportView`). The app never sees the raw
    /// numbers — it just hosts the extension inside the Aurora card.
    private var heroCard: some View {
        AuroraHeroCard {
            UsageReportView(filter: balanceFilter, context: .todayBalance)
                // Re-embed on a range change, any classification edit, or a new
                // day, so the extension re-runs makeConfiguration instead of
                // serving iOS's cached (context, filter) result. See
                // `classificationSignature` and `ReportDayTracker` (QA-9).
                .id("\(range)-\(classificationSignature)-\(dayKey)")
                // DeviceActivityReport renders in a separate process and does not
                // report its content height back to us; inside this ScrollView the
                // frame is the only thing reserving space. 300pt clipped the full
                // hero (balance + "Where it went" + reflex) once real data loaded,
                // so reserve enough for the whole design. See QA-7.
                .frame(minHeight: 420, alignment: .top)
        }
    }

    /// Today's ranked insight(s) (E7.0). The ProsperReport extension computes them
    /// from raw usage and renders the cards; we reserve a fixed height because the
    /// hosted report does not report its own size (same constraint as the hero).
    private var insightSpotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's insight").labelCaps()
            InsightSpotlightHost(filter: balanceFilter)
                .id("insights-\(range)-\(dayKey)")
                // Sized for a three-line headline and two-line evidence at the
                // card's Dynamic Type cap (InsightsReportView.maxTypeSize,
                // xLarge); 140pt clipped long app names at large text (QA-9).
                .frame(minHeight: 170, alignment: .top)
        }
    }

    private var classifyCTA: some View {
        Button { showClassify = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ProsperColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Classify your apps")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProsperColor.ink)
                    Text("Label what's productive, distracting or rest so the numbers above become yours.")
                        .font(.system(size: 12))
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Streak / milestone (real, from completed sessions)

    @ViewBuilder
    private var streakSection: some View {
        if completedCount == 0 {
            OpportunityCard(
                eyebrow: "Focus streak",
                headline: "Start your first focus session.",
                evidence: "Finish a focus block of at least 15 minutes to earn a day. Short trial blocks don't count — the streak only means something if it's real.",
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
                    Text("Pick your waste apps and sites so StolenEyes can watch for you.")
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
