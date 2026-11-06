import SwiftUI
import FamilyControls
import ManagedSettings

/// The Adult Content Guard screen (E9): switch it on once, see exactly what it
/// covers, and add to it later. There is no control on this screen that makes
/// the guard smaller, because there is none in the app.
///
/// The copy does three jobs the behaviour depends on. It names the mechanism
/// (an urge is short; a decision made in a cold state outlasts it) so the
/// permanence reads as the point rather than a limitation. It lists the gaps
/// honestly, because a guard the user overestimates is one that fails on the
/// night it matters and takes their trust with it. And it never shames: shame
/// is the fuel of the loop it is here to break.
struct AdultContentGuardView: View {
    @State private var isEnabled = false
    @State private var enabledAt: Date?
    /// What the picker has chosen. Before the guard is on this is a draft;
    /// after, it mirrors the guard's record and the picker only adds to it.
    @State private var selection = FamilyActivitySelection()
    @State private var typedDomains: [String] = []
    @State private var remainingSiteSlots = 0
    @State private var isPickerPresented = false
    @State private var domainInput = ""
    @State private var domainError: String?
    @FocusState private var domainFieldFocused: Bool

    private let guardService = AdultContentGuard.shared

    private var selectedCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var body: some View {
        Form {
            heroSection
            coverageSection
            gapsSection
            appsSection
            if isEnabled { sitesSection }
            iosSection
            exitSection
        }
        .navigationTitle("Adult Content Guard")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
        .onChange(of: isPickerPresented) { _, presented in
            // The picker lets things be unticked; the guard does not. When it
            // closes, whatever is ticked joins what was already covered.
            guard !presented, isEnabled else { return }
            guardService.add(selection: selection)
            load()
        }
        .onAppear(perform: load)
        .safeAreaInset(edge: .bottom) {
            if !isEnabled { holdToGuard }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var heroSection: some View {
        if isEnabled {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        "On since \(enabledAt?.formatted(date: .long, time: .omitted) ?? "today")",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(ProsperColor.sage)
                    Text("The decision is made. You don't have to make it again.")
                        .font(ProsperFont.insight)
                        .foregroundStyle(ProsperColor.ink)
                    Text("No off switch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Decide once, with a clear head. Then it stays decided.")
                        .font(ProsperFont.insight)
                        .foregroundStyle(ProsperColor.ink)
                    Text("Urges are short, and they arrive when you're tired, alone or stressed — exactly when willpower is thinnest. A guard you switch on each night is a nightly argument with yourself. This one is on for good, so there is no argument to lose.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var coverageSection: some View {
        Section {
            Label("Adult websites, in Safari and every other browser", systemImage: "globe")
            Label("Private Browsing in Safari", systemImage: "eye.slash")
            Label(
                isEnabled && selectedCount > 0
                    ? "^[\(selectedCount) guarded app](inflect: true)"
                    : "Any apps you add below",
                systemImage: "square.grid.2x2"
            )
        } header: {
            Text("What it blocks")
        } footer: {
            Text("Apple's own adult-content filter, plus \(AdultDomainList.builtIn.count) of the most-visited adult, cam and creator sites and the directories used to find new ones, blocked by name. iOS turns Safari's Private Browsing off while any web filter is on. All of it on this iPhone only.")
        }
    }

    private var gapsSection: some View {
        Section {
            Label("Blur photos or videos inside other apps", systemImage: "photo")
            Label("Image search results, or adult content inside apps you haven't added", systemImage: "magnifyingglass")
        } header: {
            Text("What it can't do")
        } footer: {
            Text("iOS gives no app the power to blur what another app shows. The gaps are listed so you can close them: add the usual back-door apps here, and switch on the two iOS settings below.")
        }
    }

    private var appsSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Label(isEnabled ? "Add apps to the guard" : "Pick apps to guard", systemImage: "plus.circle")
                    Spacer()
                    Text("\(selectedCount) selected")
                        .foregroundStyle(.secondary)
                }
            }
            if selectedCount > 0 {
                SelectionChips(selection: selection, placeholderCount: selectedCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if targetEnvironment(simulator)
            Label("App tokens only exist on a real iPhone with Screen Time access, so nothing can be picked in the simulator.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif
        } header: {
            Text("Apps behind the guard")
        } footer: {
            Text("Where adult content still reaches you — Reddit, X, Telegram, Discord and Tumblr are the usual ones. Guarded apps stay guarded: you can add more later, never remove one.")
        }
    }

    private var sitesSection: some View {
        Section {
            HStack {
                TextField("example.com", text: $domainInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($domainFieldFocused)
                    .onSubmit(addSite)
                Button("Add", action: addSite)
                    .disabled(domainInput.trimmingCharacters(in: .whitespaces).isEmpty || remainingSiteSlots == 0)
            }
            if let domainError {
                Text(domainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(typedDomains, id: \.self) { domain in
                Label(domain, systemImage: "globe")
            }
        } header: {
            Text("Sites you added")
        } footer: {
            Text("\(AdultDomainList.builtIn.count) sites are blocked by name and Apple's filter covers the rest. If one slips through, add it here — it is blocked for good. ^[\(remainingSiteSlots) more site](inflect: true) can be added.")
        }
    }

    private var iosSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sensitive Content Warning")
                Text("Blurs nude photos and videos before you see them in Messages, AirDrop, FaceTime, Contact Posters and shared albums, on-device. Settings ▸ Privacy & Security ▸ Sensitive Content Warning.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Close the last exit")
                Text("Deleting StolenEyes is the one way to remove the guard. To close that door too, ask someone you trust to set a Screen Time passcode you don't know and turn off Deleting Apps: Settings ▸ Screen Time ▸ Content & Privacy Restrictions ▸ iTunes & App Store Purchases ▸ Deleting Apps ▸ Don't Allow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Finish it in iOS")
        } footer: {
            Text("Two settings StolenEyes cannot switch for you. Both take a minute.")
        }
    }

    private var exitSection: some View {
        Section {
            Text(LockExitCopy.guardFull)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("How the guard ends")
        }
    }

    private var holdToGuard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permanent. No off switch, no timer, no undo.")
                .font(ProsperFont.insight)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HoldToLock(title: "Hold to guard, for good", duration: 3.0, onComplete: enable)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: - Actions

    private func load() {
        isEnabled = guardService.isEnabled
        enabledAt = guardService.enabledAt
        if isEnabled {
            selection = guardService.selection
        }
        typedDomains = guardService.typedDomains
        remainingSiteSlots = guardService.remainingSiteSlots
    }

    private func enable() {
        guardService.enable(selection: selection)
        load()
    }

    private func addSite() {
        do {
            try guardService.addSite(domainInput)
            domainInput = ""
            domainError = nil
            load()
        } catch {
            domainError = error.localizedDescription
        }
    }
}
