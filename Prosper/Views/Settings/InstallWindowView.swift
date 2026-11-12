import SwiftUI

/// Settings ▸ Install window (E9.6): pick a short daily window for installing
/// new apps, switch it on with a hold, and change it only on Friday around
/// Jumu'ah.
///
/// Like the guard's screen, it lists what the window cannot do. A rule the
/// user overestimates fails on the night it matters.
struct InstallWindowView: View {
    private let service = InstallWindowService.shared

    @State private var rule: InstallWindowRule?
    /// The window being picked: a draft before it is on, or this Friday's change.
    @State private var draft = InstallWindowRule.standard
    @State private var confirmChange = false
    @State private var confirmOff = false
    @State private var error: String?

    var body: some View {
        // Re-read each minute: the gate opens and closes, and the Friday
        // window comes and goes, while the screen is open.
        TimelineView(.everyMinute) { context in
            form(now: context.date)
        }
        .navigationTitle("Install window")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func form(now: Date) -> some View {
        let availability = service.availability(now: now)
        return Form {
            heroSection(now: now)
            if let rule {
                changeSection(rule: rule, availability: availability)
            } else {
                pickerSection
            }
            gapsSection
            exitSection
        }
        .safeAreaInset(edge: .bottom) {
            if rule == nil { holdToTurnOn }
        }
        .confirmationDialog(
            "Save until next Friday?",
            isPresented: $confirmChange,
            titleVisibility: .visible
        ) {
            Button("Save new window") { save { try service.change(to: draft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Installs will open \(Self.describe(draft)) every day. This is this Friday's one change.")
        }
        .confirmationDialog(
            "Turn the install window off?",
            isPresented: $confirmOff,
            titleVisibility: .visible
        ) {
            Button("Turn off", role: .destructive) { save { try service.turnOff() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New apps can be installed at any time again. Switching it back on is possible whenever you like.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func heroSection(now: Date) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if let rule {
                    let open = rule.window(containing: now)
                    Label(
                        open != nil ? "Open now" : "Closed to new apps",
                        systemImage: open != nil ? "arrow.down.app.fill" : "lock.app.dashed"
                    )
                    .font(.headline)
                    .foregroundStyle(open != nil ? ProsperColor.sage : ProsperColor.accent)
                    Text(status(rule: rule, open: open, now: now))
                        .font(ProsperFont.insight)
                        .foregroundStyle(ProsperColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Installs open \(Self.describe(rule)) every day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("New apps, only when you planned for them.")
                        .font(ProsperFont.insight)
                        .foregroundStyle(ProsperColor.ink)
                    Text("Harmful apps are usually looked for at a weak moment: late, alone, bored. Outside a short daily window, iOS won't install anything new. You pick the window now, with a clear head, and it can only be changed on Fridays around Jumu'ah.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var pickerSection: some View {
        Section {
            windowPickers
        } header: {
            Text("Your window")
        } footer: {
            Text("A morning slot works well: after Fajr or before work, when the day hasn't worn you down yet.")
        }
    }

    @ViewBuilder
    private var windowPickers: some View {
        DatePicker("Opens at", selection: startTime, displayedComponents: .hourAndMinute)
        Picker("For", selection: $draft.lengthMinutes) {
            ForEach(InstallWindowRule.lengths, id: \.self) { minutes in
                Text(Self.length(minutes)).tag(minutes)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private func changeSection(rule: InstallWindowRule, availability: InstallChangeWindow.Availability) -> some View {
        switch availability {
        case .open(let until):
            Section {
                windowPickers
                Button("Save new window") { confirmChange = true }
                    .disabled(draft == rule)
                Button("Turn off", role: .destructive) { confirmOff = true }
            } header: {
                Text("Change it")
            } footer: {
                Text("The Friday window is open until \(until.formatted(date: .omitted, time: .shortened)). One change per Friday: saving or turning off uses it.")
            }
        case .used(let next), .closed(let next):
            Section {
                LabeledContent("Opens at", value: Self.time(rule.startMinute))
                LabeledContent("For", value: Self.length(rule.lengthMinutes))
            } header: {
                Text("Change it")
            } footer: {
                Text(availability == .used(next: next)
                    ? "Changed already this Friday. Next chance: \(InstallWindowService.describe(next))."
                    : "Locked until Friday. Next chance to change it: \(InstallWindowService.describe(next)).")
            }
        }
    }

    private var gapsSection: some View {
        Section {
            Label("Apps you already have keep working", systemImage: "square.grid.2x2")
            Label("Changing the iPhone's clock or time zone can open the window early. Leave Date & Time on Set Automatically.", systemImage: "clock.arrow.circlepath")
        } header: {
            Text("What it can't do")
        } footer: {
            Text("To cover apps you already have, put them behind the Adult Content Guard or a lock.")
        }
    }

    private var exitSection: some View {
        Section {
            Text("Outside the Friday window there is no way to change or switch off the install window from StolenEyes, and deleting your data doesn't touch it. Deleting StolenEyes removes it, because iOS applies it on the app's behalf. That also throws away your history and your streak, which is the price.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("How it ends")
        }
    }

    private var holdToTurnOn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installs open \(Self.describe(draft)) only. Changes on Fridays, 11 AM – 1 PM.")
                .font(ProsperFont.insight)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HoldToLock(
                title: "Hold to close the App Store",
                duration: 2.0,
                accessibilityHint: "Allows new apps only in your daily window. It can only be changed on Fridays.",
                onComplete: { save { try service.turnOn(draft) } }
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: - Actions

    private var startTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: draft.startMinute / 60, minute: draft.startMinute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.startMinute = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private func load() {
        rule = service.rule
        draft = rule ?? .standard
    }

    private func save(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            self.error = error.localizedDescription
        }
        load()
    }

    private func status(rule: InstallWindowRule, open: DateInterval?, now: Date) -> String {
        if let open {
            return "You can install new apps until \(open.end.formatted(date: .omitted, time: .shortened))."
        }
        guard let next = rule.nextOpening(after: now) else { return "Opens at \(Self.time(rule.startMinute))." }
        let day = Calendar.current.isDateInToday(next) ? "today" : "tomorrow"
        return "Opens \(day) at \(next.formatted(date: .omitted, time: .shortened))."
    }

    // MARK: - Formatting

    static func time(_ minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func length(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }

    /// "7:00 – 8:00 AM"
    static func describe(_ rule: InstallWindowRule) -> String {
        "\(time(rule.startMinute)) – \(time(rule.endMinute))"
    }
}
