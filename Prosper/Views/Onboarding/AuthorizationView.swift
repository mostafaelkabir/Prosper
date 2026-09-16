import SwiftUI
import FamilyControls

struct AuthorizationView: View {
    @ObservedObject var authManager: AuthorizationManager
    @State private var showError = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("Prosper")
                    .font(.largeTitle.bold())

                Text("Take control of your screen time. Prosper needs Screen Time access to track your usage and block distracting apps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task {
                    await authManager.requestAuthorization()
                    if !authManager.isAuthorized {
                        showError = true
                    }
                }
            } label: {
                Text("Grant Access")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
        .alert("Access Required", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text("Prosper needs Screen Time access to work. Please grant access in Settings > Screen Time.")
        }
    }
}
