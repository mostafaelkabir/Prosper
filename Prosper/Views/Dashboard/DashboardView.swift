import SwiftUI
import SwiftData
import DeviceActivity

struct DashboardView: View {
    /// Reopens the setup flow from the "finish setting up" banner.
    var onResumeSetup: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]
    @Query(sort: \WarningEvent.timestamp, order: .reverse) private var warnings: [WarningEvent]
    @Query private var allSettings: [UserSettings]

    /// Bumped on appear and when the app returns to the foreground so the usage
    /// report re-queries with an up-to-date time window (its `end: .now` would
    /// otherwise be frozen at first render, leaving pickups/time stale).
    @State private var refreshToken = Date.now
    @State private var pendingPrefill: BlockPrefill?
    @State private var showCreateBlock = false

    private var settings: UserSettings? { allSettings.first }

    private var activeSession: BlockSession? {
        sessions.first { $0.isActive }
    }

    private var hasWasteList: Bool {
        (settings?.wasteAppCount ?? 0) > 0 || !(settings?.wasteDomains.isEmpty ?? true)
    }

    /// Warnings recorded since midnight; each represents one crossing of the
    /// user's daily waste threshold.
    private var todaysWarnings: [WarningEvent] {
        let start = Calendar.current.startOfDay(for: .now)
        return warnings.filter { $0.timestamp >= start }
    }

    private var wasteMinutesToday: Int? {
        guard todaysWarnings.count > 0 else { return nil }
        // We can't read the exact per-minute total from the DeviceActivity
        // extension. Each warning corresponds to one threshold crossing, so
        // the rough floor is warnings × latest threshold.
        let threshold = todaysWarnings.first?.triggerReason.parsedThresholdMinutes ?? 0
        return todaysWarnings.count * threshold
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    /// Reading `refreshToken` here ties the filter to it, so foregrounding the
    /// app produces a fresh `today()` window and the report updates.
    private var todayFilter: DeviceActivityFilter {
        _ = refreshToken
        return UsageReportFilter.today()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let settings, !settings.hasCompletedSetup {
                        setupBanner
                    }
                    if settings?.isFirstDay ?? false {
                        firstDayNote
                    }

                    heroCard
                    wasteCard

                    if let session = activeSession {
                        activeBlockCard(session)
                    } else {
                        focusCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prosper")
            .onAppear { refreshToken = .now }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshToken = .now }
            }
            .sheet(isPresented: $showCreateBlock) { CreateBlockView() }
            .sheet(item: $pendingPrefill) { CreateBlockView(prefill: $0) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.title3.weight(.semibold))
            Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero

    private var heroCard: some View {
        UsageReportView(filter: todayFilter, context: .totalTime)
            // Recreate on refresh so the report re-queries with the new window,
            // not just re-renders the cached one.
            .id(refreshToken)
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Waste

    private var wasteCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Waste today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let minutes = wasteMinutesToday {
                    Text("\(minutes)+ min")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                } else if todaysWarnings.isEmpty {
                    Text("None flagged")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("—")
                        .font(.title3)
                }
                Text("\(todaysWarnings.count) warning\(todaysWarnings.count == 1 ? "" : "s") today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: todaysWarnings.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(todaysWarnings.isEmpty ? .green : .orange)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Active block

    private func activeBlockCard(_ session: BlockSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.red)
                Text("Block active")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.remaining(session.endTime.timeIntervalSince(context.date)))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
            }
            Text("Until \(session.endTime.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if session.appCount > 0 {
                SelectionChips(
                    selection: WasteSelectionCodec.decode(session.selectionData),
                    placeholderCount: session.appCount,
                    cap: 3
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Focus (no active block)

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Start a focus block", systemImage: "lock.fill")
                .font(.headline)

            if hasWasteList, let settings {
                HStack(spacing: 10) {
                    ForEach(QuickPreset.all) { preset in
                        Button {
                            pendingPrefill = preset.prefill(from: settings)
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.label)
                                    .font(.headline)
                                Text("focus")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Locks your waste list for the chosen time. Can't be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Block distracting apps and sites for a set time. Can't be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Banners

    private var setupBanner: some View {
        Button(action: onResumeSetup) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finish setting up")
                        .font(.subheadline.weight(.semibold))
                    Text("Pick your waste apps and sites so Prosper can warn you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var firstDayNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("Prosper is learning your day. Screen Time totals fill in over the next few hours — come back tonight. The numbers below are an example.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    /// "1h 12m left", "47m left", "0m left".
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
