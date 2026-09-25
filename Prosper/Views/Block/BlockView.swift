import SwiftUI
import SwiftData

struct BlockView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showCreateBlock = false
    /// Non-nil = New Block sheet opened with a Quick Preset already applied.
    @State private var pendingPrefill: BlockPrefill?
    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]

    /// What the Lock screen shows while a block runs.
    ///
    /// SwiftData is the rich source, but it is not the only record: if the
    /// store was lost or reset mid-block, the App Group snapshot still knows the
    /// block is running. Reading SwiftData alone showed "Nothing is locked" over
    /// a live shield, and a new block then failed without a word (QA-9).
    private struct ActiveBlock {
        let startedAt: Date
        let endTime: Date
        let duration: TimeInterval
        let selectionData: Data?
        let appCount: Int
        let domains: [String]
    }

    private var activeBlock: ActiveBlock? {
        if let session = sessions.first(where: { $0.isActive }) {
            return ActiveBlock(
                startedAt: session.startedAt,
                endTime: session.endTime,
                duration: session.duration,
                selectionData: session.selectionData,
                appCount: session.appCount,
                domains: session.domains
            )
        }
        if let snapshot = SharedBlockState.active {
            return ActiveBlock(
                startedAt: snapshot.startedAt,
                endTime: snapshot.endsAt,
                duration: snapshot.duration,
                selectionData: nil,
                appCount: 0,
                domains: []
            )
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProsperColor.ground.ignoresSafeArea()

                if let block = activeBlock {
                    activeVault(block)
                } else {
                    idleContent
                }
            }
            .navigationTitle("Lock")
            .navigationBarTitleDisplayMode(activeBlock == nil ? .large : .inline)
            .sensoryFeedback(.selection, trigger: pendingPrefill)
            .sheet(isPresented: $showCreateBlock) { CreateBlockView() }
            .sheet(item: $pendingPrefill) { CreateBlockView(prefill: $0) }
        }
    }

    // MARK: - Active vault

    private func activeVault(_ session: ActiveBlock) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, session.endTime.timeIntervalSince(context.date))
            let progress = session.duration > 0 ? remaining / session.duration : 0
            VStack(spacing: 22) {
                Spacer()

                CountdownRing(
                    progress: progress,
                    centerText: formatTime(remaining),
                    size: 208,
                    emphasize: remaining <= 60
                )

                Text("Set at \(session.startedAt.formatted(date: .omitted, time: .shortened)) · until \(untilText(session.endTime))")
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink3)

                if session.appCount > 0 {
                    SelectionChips(
                        selection: WasteSelectionCodec.decode(session.selectionData),
                        placeholderCount: session.appCount
                    )
                    .padding(.horizontal, 32)
                }
                if !session.domains.isEmpty {
                    Text(session.domains.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(ProsperColor.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Text("There is no cancel. That is the point.")
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(
                RadialGradient(
                    colors: [ProsperColor.slate.opacity(0.22), .clear],
                    center: .top, startRadius: 0, endRadius: 360
                )
                .ignoresSafeArea()
            )
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "lock.open")
                    .font(.system(size: 44))
                    .foregroundStyle(ProsperColor.ink3)
                Text("Nothing is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ProsperColor.ink)
                Text("Lock distracting apps and sites for a set time — with no way to undo.")
                    .font(.subheadline)
                    .foregroundStyle(ProsperColor.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()

            quickPresetsRow

            Button {
                showCreateBlock = true
            } label: {
                Label("New block", systemImage: "lock.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var quickPresetsRow: some View {
        let settings = UserSettings.current(context: modelContext)
        let hasWaste = (settings.wasteAppCount > 0) || !settings.wasteDomains.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            if hasWaste {
                Text("Focus for").labelCaps().padding(.horizontal, 20)
                HStack(spacing: 12) {
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
                            .background(ProsperColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                Text("Locks your Settings waste list for the chosen time. Cannot be undone.")
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink3)
                    .padding(.horizontal, 20)
            } else {
                Text("Pick waste apps in Settings to unlock one-tap Focus presets.")
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink3)
                    .padding(.horizontal, 20)
            }
        }
    }

    /// The end time, with the day when it is not today (QA-9).
    private func untilText(_ end: Date) -> String {
        Calendar.current.isDateInToday(end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
