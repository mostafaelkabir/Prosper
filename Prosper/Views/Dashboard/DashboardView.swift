import SwiftUI
import SwiftData
import DeviceActivity

struct DashboardView: View {
    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]
    @Query(sort: \WarningEvent.timestamp, order: .reverse) private var warnings: [WarningEvent]

    private var activeSession: BlockSession? {
        sessions.first { $0.isActive }
    }

    /// Warnings recorded since midnight; each represents one crossing of the
    /// user's daily waste threshold.
    private var todaysWarnings: [WarningEvent] {
        let start = Calendar.current.startOfDay(for: .now)
        return warnings.filter { $0.timestamp >= start }
    }

    private var wasteMinutesToday: Int? {
        guard let count = todaysWarnings.count as Int?, count > 0 else { return nil }
        // We can't read the exact per-minute total from the DeviceActivity
        // extension. Each warning corresponds to one threshold crossing, so
        // the rough floor is warnings × latest threshold.
        let threshold = todaysWarnings.first?.triggerReason.parsedThresholdMinutes ?? 0
        return count * threshold
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UsageReportView(filter: UsageReportFilter.today(), context: .totalTime)
                        .frame(maxWidth: .infinity)
                        .frame(height: 110)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    wasteCard

                    if let session = activeSession {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.red)
                                Text("Block active until \(session.endTime.formatted(date: .omitted, time: .shortened))")
                                Spacer()
                            }
                            .font(.subheadline)

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
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Prosper")
        }
    }

    private var wasteCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Waste today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let minutes = wasteMinutesToday {
                    Text("\(minutes)+ min")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
