import SwiftUI
import SwiftData
import DeviceActivity

struct DashboardView: View {
    /// Reopens the setup flow from the "finish setting up" card.
    var onResumeSetup: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]
    @Query(sort: \WarningEvent.timestamp, order: .reverse) private var warnings: [WarningEvent]
    @Query private var allSettings: [UserSettings]

    /// Bumped on appear / foreground so the usage report re-queries with a fresh
    /// time window (its `end: .now` is otherwise frozen at first render).
    @State private var refreshToken = Date.now
    @State private var pendingPrefill: BlockPrefill?
    @State private var showCreateBlock = false

    private var settings: UserSettings? { allSettings.first }
    private var activeSession: BlockSession? { sessions.first { $0.isActive } }

    private var hasWasteList: Bool {
        (settings?.wasteAppCount ?? 0) > 0 || !(settings?.wasteDomains.isEmpty ?? true)
    }

    private var todaysWarnings: [WarningEvent] {
        let start = Calendar.current.startOfDay(for: .now)
        return warnings.filter { $0.timestamp >= start }
    }

    private var thresholdMinutes: Int { settings?.wasteWarningThresholdMinutes ?? 30 }

    /// Coarse waste estimate until E2.5b: warnings × threshold. nil = none flagged.
    private var wasteMinutesToday: Int? {
        guard !todaysWarnings.isEmpty else { return nil }
        let threshold = todaysWarnings.first?.triggerReason.parsedThresholdMinutes ?? thresholdMinutes
        return todaysWarnings.count * threshold
    }

    private var todayFilter: DeviceActivityFilter {
        _ = refreshToken
        return UsageReportFilter.today()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                        .labelCaps()
                        .padding(.horizontal, 4)

                    if let settings, !settings.hasCompletedSetup {
                        setupCard
                    }

                    heroCard
                    wasteCard
                    insightCard

                    if let session = activeSession {
                        activeBlockCard(session)
                    } else {
                        lockCard
                    }
                }
                .padding()
            }
            .background(ProsperColor.ground)
            .navigationTitle("Today")
            .onAppear { refreshToken = .now }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshToken = .now }
            }
            .sensoryFeedback(.selection, trigger: pendingPrefill)
            .sheet(isPresented: $showCreateBlock) { CreateBlockView() }
            .sheet(item: $pendingPrefill) { CreateBlockView(prefill: $0) }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        ProsperCard(padding: 0) {
            UsageReportView(filter: todayFilter, context: .totalTime)
                .id(refreshToken)
                .frame(maxWidth: .infinity)
                .frame(height: 116)
        }
    }

    // MARK: - Waste vs limit

    private var wasteCard: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 10) {
                LabelCaps("Waste today")
                if let minutes = wasteMinutesToday {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(minutes)")
                            .font(ProsperFont.hero(30))
                            .monospacedDigit()
                            .foregroundStyle(ProsperColor.ember)
                        Text("min")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ProsperColor.ink2)
                    }
                    StackedBar(waste: Double(minutes), other: Double(max(0, thresholdMinutes - minutes)))
                    Text(minutes >= thresholdMinutes
                         ? "\(minutes - thresholdMinutes)m over your \(thresholdMinutes)m limit · at least"
                         : "\(thresholdMinutes - minutes)m left of your \(thresholdMinutes)m limit")
                        .font(.footnote)
                        .foregroundStyle(minutes >= thresholdMinutes ? ProsperColor.ember : ProsperColor.ink3)
                } else {
                    Text("None flagged")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ProsperColor.sage)
                    Text("A clean run so far. Limit \(thresholdMinutes)m.")
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink3)
                }
            }
        }
    }

    // MARK: - Insight (honest until E7.0)

    private var insightCard: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 10) {
                LabelCaps("Noticed today")
                insightSentence
            }
        }
    }

    @ViewBuilder
    private var insightSentence: some View {
        if settings?.isFirstDay ?? false {
            InsightSentence(
                text: "Prosper is still learning your day.",
                footnote: "Come back tonight for your first read."
            )
        } else if let count = wasteMinutesToday.map({ _ in todaysWarnings.count }), count > 0 {
            InsightSentence(
                text: "You slipped past your waste limit \(count) time\(count == 1 ? "" : "s") today.",
                footnote: "Limit \(thresholdMinutes)m · tap Lock to close the door."
            )
        } else {
            InsightSentence(
                text: "A clean run so far — nothing has pulled you off today.",
                footnote: hasWasteList ? nil : "Set a waste list so Prosper can watch for you."
            )
        }
    }

    // MARK: - Active block

    private func activeBlockCard(_ session: BlockSession) -> some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, session.endTime.timeIntervalSince(context.date))
                    let progress = session.duration > 0 ? remaining / session.duration : 0
                    HStack(spacing: 14) {
                        CountdownRing(progress: progress, centerText: "", caption: nil, size: 44, lineWidth: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            LabelCaps("Locked")
                            Text(Self.remaining(remaining))
                                .font(ProsperFont.dataRow.weight(.semibold))
                                .foregroundStyle(ProsperColor.ink)
                        }
                        Spacer()
                        Text("until \(session.endTime.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(ProsperColor.ink3)
                    }
                }
                if session.appCount > 0 {
                    SelectionChips(
                        selection: WasteSelectionCodec.decode(session.selectionData),
                        placeholderCount: session.appCount,
                        cap: 3
                    )
                }
            }
        }
    }

    // MARK: - Lock (no active block)

    private var lockCard: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 12) {
                LabelCaps("Lock the waste list")
                if hasWasteList, let settings {
                    HStack(spacing: 10) {
                        ForEach(QuickPreset.all) { preset in
                            Button {
                                pendingPrefill = preset.prefill(from: settings)
                            } label: {
                                VStack(spacing: 3) {
                                    Text(preset.label)
                                        .font(.headline)
                                        .foregroundStyle(ProsperColor.ink)
                                    Text("focus").labelCaps()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(ProsperColor.card2)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink3)
                } else {
                    Button {
                        showCreateBlock = true
                    } label: {
                        Text("New block")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Block distracting apps and sites for a set time. Cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink3)
                }
            }
        }
    }

    // MARK: - Setup card

    private var setupCard: some View {
        Button(action: onResumeSetup) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish setting up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ProsperColor.ink)
                    Text("Pick your waste apps and sites so Prosper can watch for you.")
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ProsperColor.slate)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProsperColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private static func remaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m left" }
        return "\(minutes)m left"
    }
}

private extension String {
    /// Pulls a minutes count from a reason string like "Waste activity reached 30 minutes today".
    var parsedThresholdMinutes: Int {
        let scanner = Scanner(string: self)
        scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
        var value = 0
        _ = scanner.scanInt(&value)
        return value
    }
}
