import SwiftUI
import SwiftData
import DeviceActivity

struct DashboardView: View {
    @Query(sort: \BlockSession.startedAt, order: .reverse) private var sessions: [BlockSession]

    private var activeSession: BlockSession? {
        sessions.first { $0.isActive }
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

                    if let session = activeSession {
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.red)
                            Text("Block active until \(session.endTime.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                        }
                        .font(.subheadline)
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
}
