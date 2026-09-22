import SwiftUI
import FamilyControls

/// The Screen Time gate. Every state it can be in says what happened and what,
/// if anything, the user can do — including the states where the honest answer
/// is that Prosper will not work on this account (REL-10).
struct AuthorizationView: View {
    @ObservedObject var authManager: AuthorizationManager
    @Environment(\.openURL) private var openURL

    private var state: AuthorizationManager.State { authManager.state }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)

                VStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 56))
                        .foregroundStyle(iconTint)
                        .accessibilityHidden(true)

                    Text("Prosper")
                        .font(.largeTitle.bold())
                        .foregroundStyle(ProsperColor.ink)

                    Text(state.title)
                        .font(.headline)
                        .foregroundStyle(ProsperColor.ink)
                        .multilineTextAlignment(.center)

                    Text(state.explanation)
                        .font(.body)
                        .foregroundStyle(ProsperColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                if let caveat = state.blockCaveat {
                    Text(caveat)
                        .font(.footnote)
                        .foregroundStyle(ProsperColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                }

                actions
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
        }
        .background(ProsperColor.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if state.canRequest {
                Button {
                    Task { await authManager.requestAuthorization() }
                } label: {
                    Group {
                        if authManager.isRequesting {
                            ProgressView()
                        } else {
                            Text("Grant Access")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(authManager.isRequesting)
            }

            if state.pointsToSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                // Deep-linking straight to Screen Time is private API, so the
                // route is spelled out instead of guessed at.
                Text("Settings ▸ Screen Time ▸ Apps With Screen Time Access ▸ Prosper")
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink2)
                    .multilineTextAlignment(.center)
            }

            // A state that cannot be re-requested can still be re-checked: the
            // user may have just changed it in Settings and come back.
            if !state.canRequest {
                Button("Check again") { authManager.refresh() }
                    .font(.subheadline)
                    .padding(.top, 4)
            }
        }
    }

    private var icon: String {
        switch state {
        case .authorized: "checkmark.shield.fill"
        case .notDetermined: "shield.checkered"
        case .denied: "shield.slash"
        case .restricted: "person.crop.circle.badge.exclamationmark"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    private var iconTint: Color {
        switch state {
        case .authorized: ProsperColor.accent
        case .notDetermined: ProsperColor.slate
        default: ProsperColor.ember
        }
    }
}

#Preview("Not determined") {
    AuthorizationView(authManager: AuthorizationManager())
}
