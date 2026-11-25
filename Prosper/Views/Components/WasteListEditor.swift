import SwiftUI
import FamilyControls

/// The apps / websites / threshold editor for the user's waste list. Rendered
/// as a set of `Form` `Section`s so it can be embedded in both Settings and the
/// onboarding setup flow. The parent owns the state and persists via `onChange`.
struct WasteListEditor: View {
    @Binding var selection: FamilyActivitySelection
    @Binding var typedDomains: [String]
    @Binding var thresholdMinutes: Double
    /// Called after any edit so the parent can persist and refresh the schedule.
    var onChange: () -> Void

    /// True while a finger is on the threshold slider. Each 5-minute step used
    /// to persist and reinstall the waste monitor, restarting iOS's count for
    /// the day several times per drag; now only where it lands counts (QA-9).
    @State private var isDraggingThreshold = false

    var body: some View {
        Group {
            appsSection
            websitesSection
            thresholdSection
        }
        .onChange(of: thresholdMinutes) { _, _ in
            // Keyboard and VoiceOver adjustments have no drag to end, so they
            // still persist straight away.
            if !isDraggingThreshold { onChange() }
        }
    }

    /// The same rows as the Lock tab's block list: it is the same list (UX-28).
    private var appsSection: some View {
        Section {
            AppsPickRow(selection: $selection, onChange: onChange)
        } header: {
            Text("Your block list")
        } footer: {
            Text("The apps that eat your time. Warnings count time in the apps and Screen Time categories you pick here, and the Lock tab locks them.")
        }
    }

    private var websitesSection: some View {
        Section {
            SitesPickRow(domains: $typedDomains, onChange: onChange)
        } footer: {
            Text("Locked along with the apps. iOS can't measure time on a typed site, so sites don't count toward warnings.")
        }
    }

    private var thresholdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Warn after")
                    Spacer()
                    Text("\(Int(thresholdMinutes)) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $thresholdMinutes, in: 5...240, step: 5) { editing in
                    isDraggingThreshold = editing
                    if !editing { onChange() }
                }
            }
        } header: {
            Text("Threshold")
        } footer: {
            Text("Combined time across the apps and categories you picked in a single day before Stolen Glance warns you, then keeps warning: \(WarningLevel.ladderText(base: Int(thresholdMinutes)))")
        }
    }
}
