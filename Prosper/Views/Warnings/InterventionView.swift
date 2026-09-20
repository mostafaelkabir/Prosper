import SwiftUI
import SwiftData

/// The level-3 intervention (E4.3 / E4.4): the one warning that does not wait
/// politely in Notification Centre. `ProsperMonitor` flags it from the
/// background; the app shows it full-screen on the next open and — unless the
/// user turned the phrase off — only lets it go once they have typed out what
/// they are choosing.
///
/// It cannot start or stop a block. Deciding is the user's job; this screen
/// only makes the number impossible to scroll past.
struct InterventionView: View {
    /// Minutes of waste time that tripped the intervention.
    let minutes: Int
    /// When false, a single button dismisses it (Settings → typed phrase off).
    var requiresPhrase: Bool
    /// Dismiss and hand over to the Lock tab so the user can act immediately.
    var onLockItDown: () -> Void
    var onAcknowledge: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    static let phrase = "I choose to waste my time"

    private var phraseMatches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(Self.phrase) == .orderedSame
    }

    private var canDismiss: Bool { !requiresPhrase || phraseMatches }

    var body: some View {
        ZStack {
            ProsperColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    VStack(alignment: .leading, spacing: 2) {
                        HeroNumber(value: WarningLevel.durationText(minutes), size: 56)
                        Text("on distractions today")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ProsperColor.ink2)
                    }
                    InsightSentence(
                        text: "That is three times the limit you set for yourself. Nothing is blocked right now — this is only Prosper telling you the truth.",
                        footnote: "Your threshold: \(WarningLevel.durationText(minutes / WarningLevel.intervention.rawValue)) a day."
                    )
                    if requiresPhrase { phraseField }
                    actions
                }
                .padding(24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ProsperColor.ember)
            Text("Third warning today")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ProsperColor.ember)
        }
        .padding(.top, 32)
    }

    private var phraseField: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("To close this, type")
                    .font(.footnote)
                    .foregroundStyle(ProsperColor.ink2)
                Text(Self.phrase)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ProsperColor.ink)
            }
            TextField("", text: $typed)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { fieldFocused = false }
                .font(.body)
                .foregroundStyle(ProsperColor.ink)
                .padding(14)
                .background(ProsperColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            phraseMatches ? ProsperColor.accent : ProsperColor.line,
                            lineWidth: 1
                        )
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: phraseMatches)
                .accessibilityLabel("Type the phrase \(Self.phrase) to dismiss")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            FocusCTA(title: "Lock it down") {
                acknowledge()
                onLockItDown()
            }
            Button {
                acknowledge()
                onAcknowledge()
            } label: {
                Text(requiresPhrase ? "Keep going anyway" : "I understand")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 45)
                    .foregroundStyle(canDismiss ? ProsperColor.ink2 : ProsperColor.unclassified)
                    .background(ProsperColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canDismiss)
        }
    }

    /// Clears the pending flag and stamps the stored warnings as acknowledged,
    /// so the history shows what the user did rather than only what fired.
    private func acknowledge() {
        WarningInterventionState.clear()

        let level = WarningLevel.intervention.rawValue
        let descriptor = FetchDescriptor<WarningEvent>(
            predicate: #Predicate<WarningEvent> { $0.level == level && !$0.acknowledged }
        )
        if let pending = try? modelContext.fetch(descriptor) {
            for event in pending {
                event.acknowledged = true
                event.acknowledgedAt = .now
            }
            try? modelContext.save()
        }
    }
}

#Preview("Phrase required") {
    InterventionView(minutes: 90, requiresPhrase: true, onLockItDown: {}, onAcknowledge: {})
        .modelContainer(for: WarningEvent.self, inMemory: true)
}

#Preview("Single tap") {
    InterventionView(minutes: 90, requiresPhrase: false, onLockItDown: {}, onAcknowledge: {})
        .modelContainer(for: WarningEvent.self, inMemory: true)
}
