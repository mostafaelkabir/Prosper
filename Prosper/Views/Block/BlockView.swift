import SwiftUI
import SwiftData
import Combine

struct BlockView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showCreateBlock = false
    /// Non-nil = New Block sheet opened with a Quick Preset already applied.
    @State private var pendingPrefill: BlockPrefill?
    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]
    @State private var now = Date.now

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var activeSession: BlockSession? {
        sessions.first { $0.isActive }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let session = activeSession {
                    activeBlockContent(session)
                } else {
                    emptyBlockContent
                }

                Spacer()

                if activeSession == nil {
                    quickPresetsRow

                    Button {
                        showCreateBlock = true
                    } label: {
                        Label("New Block", systemImage: "lock.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Lock")
            .sheet(isPresented: $showCreateBlock) {
                CreateBlockView()
            }
            .sheet(item: $pendingPrefill) { prefill in
                CreateBlockView(prefill: prefill)
            }
            .onReceive(timer) { now = $0 }
        }
    }

    private func activeBlockContent(_ session: BlockSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Block Active")
                .font(.title3.weight(.semibold))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(formatTime(max(0, session.endTime.timeIntervalSince(context.date))))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            Text("Until \(session.endTime.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("\(session.appCount) app\(session.appCount == 1 ? "" : "s")", systemImage: "app.fill")
                Label("\(session.domainCount) site\(session.domainCount == 1 ? "" : "s")", systemImage: "globe")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var emptyBlockContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No active blocks")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Block distracting apps and websites\nfor a set time with no way to undo.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }


    private var quickPresetsRow: some View {
        let settings = UserSettings.current(context: modelContext)
        let hasWaste = (settings.wasteAppCount > 0) || !settings.wasteDomains.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            if hasWaste {
                Text("Focus for")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                HStack(spacing: 12) {
                    ForEach(QuickPreset.all) { preset in
                        Button {
                            pendingPrefill = preset.prefill(from: settings)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: preset.systemImage)
                                    .font(.title2)
                                Text(preset.label)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                Text("Locks your Settings waste list for the chosen duration. Cannot be undone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            } else {
                Text("Pick waste apps in Settings to unlock one-tap Focus presets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
        }
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
