import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Text("Settings")
                .font(.title2)
                .foregroundStyle(.secondary)
                .navigationTitle("Settings")
        }
    }
}
