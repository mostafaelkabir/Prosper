import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var setup: SystemSetup

    var body: some View {
        ScreenScroll {
            ProtectionSection(setup: setup)
            GuardSection()
            BrowserSection()
            ProsperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Daily goal").labelCaps()
                    Stepper(value: Binding(get: { model.settings.dailyDistractingGoalMinutes }, set: { model.setGoal(minutes: $0) }), in: 15...480, step: 15) {
                        Text("At most \(Double(model.settings.dailyDistractingGoalMinutes * 60).usageFormatted) of distracting time a day")
                            .font(.system(size: 13)).foregroundStyle(ProsperColor.ink)
                    }
                }
            }
            ProsperCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How a lock ends").labelCaps()
                    Text(MacCopy.lockExitFull).font(.system(size: 13)).foregroundStyle(ProsperColor.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { setup.refresh() }
    }
}

struct ProtectionSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var setup: SystemSetup

    var body: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Protection").labelCaps()
                    Spacer()
                    Button(setup.allOn ? "Check again" : "Set up / repair") {
                        setup.installEverything()
                        model.finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent).tint(ProsperColor.accent)
                }
                StatusLine(title: "Network filter extension", state: setup.extensionState, detail: "Approved once in System Settings → General → Login Items & Extensions → Network Extensions.")
                StatusLine(title: "Content filter", state: filterState, detail: filterDetail)
                StatusLine(title: "DNS proxy", state: dnsState, detail: dnsDetail)
                StatusLine(title: "Background helper", state: agentState, detail: agentDetail)
                if case .needsApproval = setup.agentState {
                    Button("Open Login Items settings") { setup.openLoginItemsSettings() }.buttonStyle(.bordered)
                }
                if let status = model.status?.filter {
                    HStack(spacing: 12) {
                        StatTile(value: "\(status.blockedToday)", label: "Blocked today")
                        StatTile(value: "\(status.safeSearchRewritesToday)", label: "SafeSearch answers")
                        StatTile(value: "\(status.unnamedToday)", label: "Unnamed connections", footnote: "Allowed and counted")
                    }
                }
            }
        }
    }

    /// The setting says on; the extension's own answer says whether it is running.
    private var filterState: SystemSetup.StepState {
        guard setup.filterState.isOn else { return setup.filterState }
        if let f = model.status?.filter, f.filterStartedAt != nil { return .on }
        if model.agentRunning, model.status?.filterError != nil { return .failed("Switched on, but the filter is not answering.") }
        return setup.filterState
    }

    private var filterDetail: String {
        if let started = model.status?.filter?.filterStartedAt {
            return "Running since \(started.formatted(date: .abbreviated, time: .shortened)). Rules revision \(model.status?.filter?.rulesRevision ?? 0)."
        }
        return model.status?.filterError ?? "Blocks locked and adult sites in every browser and app."
    }

    private var dnsState: SystemSetup.StepState {
        guard setup.dnsState.isOn else { return setup.dnsState }
        if let f = model.status?.filter, f.dnsStartedAt == nil { return .working }
        return .on
    }

    private var dnsDetail: String {
        if let started = model.status?.filter?.dnsStartedAt {
            return "Running since \(started.formatted(date: .abbreviated, time: .shortened)). Forces SafeSearch while the guard is on."
        }
        return "Answers DNS for the guard and SafeSearch."
    }

    private var agentState: SystemSetup.StepState {
        if model.agentRunning { return .on }
        if setup.agentState.isOn { return .failed("Registered, but not running. It restarts within seconds; if this stays red, log out and back in.") }
        return setup.agentState
    }

    private var agentDetail: String {
        if let s = model.status, model.agentRunning {
            return "Running since \(s.agentStartedAt.formatted(date: .abbreviated, time: .shortened)). Measures time and closes locked apps."
        }
        return "Measures time and closes locked apps."
    }
}

struct StatusLine: View {
    let title: String
    let state: SystemSetup.StepState
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ProsperColor.ink)
                    Text(label).font(.system(size: 12)).foregroundStyle(color)
                }
                Text(message).font(.system(size: 12)).foregroundStyle(ProsperColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var label: String {
        switch state {
        case .on: "On"
        case .off: "Off"
        case .working: "Working…"
        case .needsApproval: "Needs your approval"
        case .failed: "Not working"
        case .unknown: "Checking…"
        }
    }

    private var message: String {
        switch state {
        case .needsApproval(let text), .failed(let text): text
        default: detail
        }
    }

    private var color: Color {
        switch state {
        case .on: ProsperColor.productive
        case .working, .unknown: ProsperColor.unclassified
        case .needsApproval: ProsperColor.rest
        case .off, .failed: ProsperColor.distracting
        }
    }
}

struct GuardSection: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = LockSelection()
    @State private var showAdd = false

    var body: some View {
        ProsperCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(ProsperColor.accent)
                    Text("Adult Content Guard").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ProsperColor.ink)
                    Spacer()
                    if let state = model.rules.guardState {
                        Text("On since \(state.enabledAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(ProsperColor.productive)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("What it does").labelCaps()
                    ForEach(MacCopy.guardCovers, id: \.self) { line in
                        Label(line, systemImage: "checkmark").font(.system(size: 13)).foregroundStyle(ProsperColor.ink)
                    }
                    Text("What it can't reach").labelCaps().padding(.top, 6)
                    ForEach(MacCopy.guardCannot, id: \.self) { line in
                        Label(line, systemImage: "minus").font(.system(size: 13)).foregroundStyle(ProsperColor.ink2)
                    }
                }
                Text(MacCopy.guardFull).font(.system(size: 12)).foregroundStyle(ProsperColor.ink2).fixedSize(horizontal: false, vertical: true)

                if let state = model.rules.guardState {
                    StatusLine(title: "Screen Guard", state: screenGuardState, detail: "Checks the window in front of browsers, image viewers, video players and chat apps for explicit images, on this Mac only, and covers the screen when it finds one.")
                    if !state.extraDomains.isEmpty || !state.bundleIDs.isEmpty {
                        Text("Also behind it").labelCaps()
                        ItemsLine(platformIDs: [], domains: state.extraDomains, bundleIDs: state.bundleIDs, appNames: state.appNames)
                    }
                    Button("Add sites or apps…") { showAdd = true }.buttonStyle(.bordered)
                    Text("Additions are permanent too. While the guard is on, QUIC, browser secure DNS and iCloud Private Relay stay off so every connection keeps its name.")
                        .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
                } else {
                    HoldToConfirmButton(title: "Hold to turn on the guard, for good", systemImage: "shield.lefthalf.filled", duration: 3) {
                        _ = model.enableGuard()
                    }
                    Text("There is no off switch after this. Decide with a clear head.")
                        .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add to the guard").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("These stay blocked for as long as StolenEyes is installed. Nothing can be taken out.")
                    .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2)
                ScrollView { LockItemsPicker(selection: $selection, showPlatforms: false) }
                HStack {
                    Button("Cancel") { showAdd = false }
                    Spacer()
                    HoldToConfirmButton(title: "Hold to add for good", systemImage: "plus", enabled: !selection.isEmpty) {
                        if model.addToGuard(domains: selection.domains, apps: Array(selection.apps)) {
                            selection = LockSelection()
                            showAdd = false
                        }
                    }
                    .frame(width: 240)
                }
            }
            .padding(24)
            .frame(width: 560, height: 560)
            .background(ProsperColor.background)
        }
    }
}

extension GuardSection {
    var screenGuardState: SystemSetup.StepState {
        switch model.status?.screenGuard ?? .off {
        case .running: .on
        case .off: model.agentRunning ? .working : .failed("The background helper is not running.")
        case .needsScreenRecording: .needsApproval("Allow StolenEyes Agent in System Settings → Privacy & Security → Screen & System Audio Recording.")
        case .sensitiveContentWarningOff: .needsApproval("Turn on System Settings → Privacy & Security → Sensitive Content Warning. It is the one setting StolenEyes cannot switch on for you; Apple's classifier only runs while it is on.")
        case .unavailable: .failed("This build is signed without Apple's Sensitive Content Analysis capability. It arrives with the full build (network filter included).")
        }
    }
}

struct BrowserSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ProsperCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Websites per browser").labelCaps()
                Text("To count time per site and close a tab on a locked site, the helper reads the address of the tab you are on. macOS asks once per browser. Only the site name is kept.")
                    .font(.system(size: 12)).foregroundStyle(ProsperColor.ink2).fixedSize(horizontal: false, vertical: true)
                let access = model.status?.browserAccess ?? [:]
                if access.isEmpty {
                    Text("No browser used yet since the helper started.").font(.system(size: 12)).foregroundStyle(ProsperColor.unclassified)
                }
                ForEach(access.keys.sorted(), id: \.self) { id in
                    HStack {
                        Text(InstalledApps.named(id).name).font(.system(size: 13)).foregroundStyle(ProsperColor.ink)
                        Spacer()
                        Text(access[id] == true ? "Allowed" : "Refused: allow StolenEyes Agent in System Settings → Privacy & Security → Automation")
                            .font(.system(size: 12)).foregroundStyle(access[id] == true ? ProsperColor.productive : ProsperColor.distracting)
                    }
                }
                Text("Blocking does not depend on this: the network filter blocks locked sites in every browser either way.")
                    .font(.system(size: 11)).foregroundStyle(ProsperColor.unclassified)
            }
        }
    }
}
