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
    /// Drives the staggered reveal of a step's content.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stepCount = 3

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                Group {
                    switch step {
                    case 0: wasteStep
                    case 1: notificationsStep
                    default: lockStep
                    }
                }
                // Each step slides in from the side it comes from, so three
                // screens read as one short path with an end (UX-30).
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)
            }
            .background(ProsperColor.ground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { skip() }
                }
            }
            .onAppear {
                loadIfNeeded()
                revealed = true
            }
        }
    }

    /// Where you are and how little is left: three short bars.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? ProsperColor.accent : ProsperColor.line)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.3), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(Self.stepCount)")
    }

    private func go(to next: Int) {
        revealed = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { step = next }
        // The new step's content rises in once it is on screen.
        DispatchQueue.main.async { revealed = true }
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
                    Text("Pick the apps that eat your time and Stolen Glance warns you when today's total crosses your threshold. Add sites too — they join your one-tap Focus block, though iOS can't time them for warnings.")
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
                Button("Continue") { go(to: 1) }
                    .buttonStyle(AuroraButtonStyle())
            }
        }
    }

    private var notificationsStep: some View {
        // Scrolls when large text makes it taller than the screen (UX-27).
        FitOrScroll { VStack(spacing: 24) {
            Spacer()
            stepMark("bell.badge.fill")
                .modifier(Rise(shown: revealed, order: 0, reduceMotion: reduceMotion))
            Text("Let a warning reach you")
                .font(.title2.bold())
                .foregroundStyle(ProsperColor.ink)
                .multilineTextAlignment(.center)
                .modifier(Rise(shown: revealed, order: 1, reduceMotion: reduceMotion))
            Text("Notifications arrive inside Instagram or Safari the moment you cross your limit, not buried on a screen you never open.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ProsperColor.ink2)
                .padding(.horizontal, 32)
                .modifier(Rise(shown: revealed, order: 2, reduceMotion: reduceMotion))
            Spacer()
            VStack(spacing: 6) {
                Button("Enable notifications") {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        go(to: 2)
                    }
                }
                .buttonStyle(AuroraButtonStyle())

                Button("Not now") { go(to: 2) }
                    .scaledFont(16, weight: .medium)
                    .foregroundStyle(ProsperColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        } }
    }

    /// The last thing setup says, because it is the thing a user most needs to
    /// have heard before their first block rather than during it: the lock is
    /// real, and the one way out is deleting the app (REL-8).
    private var lockStep: some View {
        FitOrScroll { VStack(spacing: 24) {
            Spacer()
            stepMark("lock.shield")
                .modifier(Rise(shown: revealed, order: 0, reduceMotion: reduceMotion))
            Text("A block cannot be canceled")
                .font(.title2.bold())
                .foregroundStyle(ProsperColor.ink)
                .multilineTextAlignment(.center)
                .modifier(Rise(shown: revealed, order: 1, reduceMotion: reduceMotion))
            Text(LockExitCopy.full)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .modifier(Rise(shown: revealed, order: 2, reduceMotion: reduceMotion))
            Spacer()
            Button("Got it", action: finish)
                .buttonStyle(AuroraButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        } }
    }

    /// The step's symbol on a soft violet disc.
    private func stepMark(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 40, weight: .semibold))
            .foregroundStyle(ProsperColor.accent)
            .frame(width: 96, height: 96)
            .background(ProsperColor.accent.opacity(0.14))
            .clipShape(Circle())
            .accessibilityHidden(true)
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
