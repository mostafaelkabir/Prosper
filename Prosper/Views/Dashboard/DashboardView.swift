import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            Text("Dashboard")
                .font(.title2)
                .foregroundStyle(.secondary)
                .navigationTitle("Prosper")
        }
    }
}
