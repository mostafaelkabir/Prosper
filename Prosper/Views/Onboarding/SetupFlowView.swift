import SwiftUI
import SwiftData
import FamilyControls

/// Post-authorization setup: pick the waste list, opt into notifications, then
/// hear how a block ends before ever starting one (REL-8). Skippable at any
/// point and resumable later from the Dashboard banner or the "Set up again"
/// entry in Settings.
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
                switch step {
                case 0: wasteStep
                case 1: notificationsStep
                default: lockStep
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { skip() }
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private var title: String {
        switch step {
        case 0: "What wastes your time?"
        case 1: "Stay in the loop"
        default: "How a block ends"
        }
    }

    // MARK: - Steps

    private var wasteStep: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Pick the apps that eat your time and StolenEyes warns you when today's total crosses your threshold. Add sites too — they join your one-tap Focus block, though iOS can't time them for warnings.")
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
            Text("Notifications arrive inside Instagram or Safari the moment you cross your limit — not buried on a screen you never open.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        step = 2
                    }
                } label: {
                    Text("Enable notifications")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") { step = 2 }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    /// The last thing setup says, because it is the thing a user most needs to
    /// have heard before their first block rather than during it: the lock is
    /// real, and the one way out is deleting the app (REL-8).
    private var lockStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("A block cannot be cancelled")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(LockExitCopy.full)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Spacer()
            Button {
                finish()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
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
        s.syncClassificationSnapshot()

        WarningService.shared.refreshSchedule(
            enabled: s.warningsEnabled,
            selection: selection,
            typedDomains: typedDomains,
            thresholdMinutes: Int(thresholdMinutes)
        )
    }

    /// Bail out early: keep whatever waste list was entered, but leave setup
    /// marked incomplete so the Dashboard banner keeps offering to resume.
    /// The skip itself is remembered so setup stops opening on every launch
    /// (QA-9).
    private func skip() {
        persist()
        SetupSkip.markSkipped()
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

/// Whether the user chose "Skip" in setup (QA-9).
///
/// Kept in standard defaults rather than on `UserSettings` so no schema
/// migration is needed, and because only the app ever asks. Setup opens by
/// itself only when it is neither finished nor skipped; the Dashboard banner
/// and "Set up again" still reach it.
enum SetupSkip {
    private static let key = "setup.skipped"

    static var isSkipped: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markSkipped() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
