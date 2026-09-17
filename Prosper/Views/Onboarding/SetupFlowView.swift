import SwiftUI
import SwiftData
import FamilyControls

/// Post-authorization setup: pick the waste list, then opt into notifications.
/// Skippable at any point and resumable later from the Dashboard banner or the
/// "Set up again" entry in Settings.
struct SetupFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var step = 0
    @State private var selection = FamilyActivitySelection()
    @State private var typedDomains: [String] = []
    @State private var thresholdMinutes: Double = 30
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    wasteStep
                } else {
                    notificationsStep
                }
            }
            .navigationTitle(step == 0 ? "What wastes your time?" : "Stay in the loop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { skip() }
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - Steps

    private var wasteStep: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Pick the apps and sites that eat your time. Prosper watches these to warn you when today's total crosses your threshold — and they become your one-tap Focus block.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                WasteListEditor(
                    selection: $selection,
                    typedDomains: $typedDomains,
                    thresholdMinutes: $thresholdMinutes,
                    onChange: persist
                )
            }
            bottomBar {
                Button {
                    step = 1
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Let a warning reach you")
                .font(.title2.bold())
            Text("So a warning can reach you inside Instagram or Safari the moment you cross your limit — not buried on a screen you never open.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        finish()
                    }
                } label: {
                    Text("Enable notifications")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") { finish() }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private func bottomBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let s = UserSettings.current(context: modelContext)
        selection = WasteSelectionCodec.decode(s.wasteAppSelectionData)
        typedDomains = s.wasteDomains
        thresholdMinutes = Double(max(5, s.wasteWarningThresholdMinutes))
    }

    private func persist() {
        let s = UserSettings.current(context: modelContext)
        s.wasteAppSelectionData = WasteSelectionCodec.encode(selection)
        s.wasteAppCount = selection.applicationTokens.count + selection.categoryTokens.count
        s.wasteDomains = typedDomains
        s.wasteWarningThresholdMinutes = Int(thresholdMinutes)
        try? modelContext.save()

        WarningService.shared.refreshSchedule(
            enabled: s.warningsEnabled,
            selection: selection,
            typedDomains: typedDomains,
            thresholdMinutes: Int(thresholdMinutes)
        )
    }

    /// Bail out early: keep whatever waste list was entered, but leave setup
    /// marked incomplete so the Dashboard banner keeps offering to resume.
    private func skip() {
        persist()
        dismiss()
    }

    /// Reached the end of the flow: mark setup complete so the banner clears.
    private func finish() {
        persist()
        let s = UserSettings.current(context: modelContext)
        s.hasCompletedSetup = true
        try? modelContext.save()
        dismiss()
    }
}
