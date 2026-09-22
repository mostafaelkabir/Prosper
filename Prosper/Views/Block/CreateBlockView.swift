import SwiftUI
import SwiftData
import FamilyControls

struct CreateBlockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selection: FamilyActivitySelection
    @State private var domains: [String]
    @State private var domainInput = ""
    @State private var domainError: String?
    @FocusState private var domainFieldFocused: Bool
    @State private var isPickerPresented = false
    @State private var duration: TimeInterval
    @State private var showCustomPicker = false
    @State private var customHours = 1
    @State private var customMinutes = 0
    @State private var showConfirmation = false

    /// Every block ever started, used only to tell a first-timer from someone
    /// who knows what a block feels like.
    @Query private var allSessions: [BlockSession]

    /// Prefill hook for Quick Block presets: seed the sheet with the user's
    /// waste selection + typed domains and a chosen duration. The user still
    /// completes the hold-to-lock. `nil` = manual entry.
    init(prefill: BlockPrefill? = nil) {
        _selection = State(initialValue: prefill?.selection ?? FamilyActivitySelection())
        _domains = State(initialValue: prefill?.domains ?? [])
        _duration = State(initialValue: prefill?.duration ?? 3600)
    }

    private var endTimeText: String {
        Date.now.addingTimeInterval(duration).formatted(date: .omitted, time: .shortened)
    }

    private let allPresets: [(label: String, seconds: TimeInterval)] = [
        ("30m", 1800),
        ("1h", 3600),
        ("2h", 7200),
        ("4h", 14400),
        ("8h", 28800),
    ]

    /// A first block is capped well below the 23h55m the custom picker allows.
    ///
    /// Someone who has never felt an unbreakable block has no way to judge what
    /// a day of one is like, and there is no undo to learn from. Four hours is
    /// long enough to be a real session and short enough that a misjudgement is
    /// an afternoon rather than a crisis. The cap lifts as soon as they have
    /// finished one (REL-9).
    private static let firstBlockMaxDuration: TimeInterval = 4 * 3600

    private var isFirstBlock: Bool { allSessions.isEmpty }

    private var maxDuration: TimeInterval {
        isFirstBlock ? Self.firstBlockMaxDuration : 23 * 3600 + 55 * 60
    }

    private var presets: [(label: String, seconds: TimeInterval)] {
        allPresets.filter { $0.seconds <= maxDuration }
    }

    private var maxCustomHours: Int { Int(maxDuration) / 3600 }

    private static let suggestedDomains: [(name: String, domain: String)] = [
        ("Reddit", "reddit.com"),
        ("YouTube", "youtube.com"),
        ("X", "x.com"),
        ("Instagram", "instagram.com"),
        ("TikTok", "tiktok.com"),
        ("Facebook", "facebook.com"),
    ]

    private var siteCount: Int {
        selection.webDomainTokens.count + domains.count
    }

    private var hasSelection: Bool {
        !selection.applicationTokens.isEmpty
            // A category-only pick is a real selection — and the one REL-9 cares
            // most about, since it sweeps in apps the user never named. It used
            // to leave the lock button hidden with no explanation.
            || !selection.categoryTokens.isEmpty
            || siteCount > 0
    }

    private var durationText: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "\(minutes) minutes"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                appsSection
                websitesSection
                durationSection
            }
            .navigationTitle("New Block")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if hasSelection {
                    confirmBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .sensoryFeedback(.selection, trigger: duration)
            .onAppear {
                loadSavedDomains()
                clampDuration()
            }
            .navigationDestination(isPresented: $showConfirmation) {
                ConfirmBlockView(
                    selection: selection,
                    typedDomains: domains,
                    duration: duration,
                    onConfirm: startBlock
                )
            }
        }
    }

    private var appsSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Label("Select Apps", systemImage: "apps.iphone")
                    Spacer()
                    if !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty {
                        Text("\(selection.applicationTokens.count + selection.webDomainTokens.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty {
                SelectionChips(
                    selection: selection,
                    placeholderCount: selection.applicationTokens.count
                        + selection.categoryTokens.count
                        + selection.webDomainTokens.count
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Apps")
        } footer: {
            Text("To block the YouTube or Reddit app itself, pick it here. Websites are added below.")
        }
    }

    private var websitesSection: some View {
        Section {
            HStack {
                TextField("reddit.com", text: $domainInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .focused($domainFieldFocused)
                    .onSubmit(addTypedDomain)
                Button("Add", action: addTypedDomain)
                    .disabled(domainInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let domainError {
                Text(domainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(domains, id: \.self) { domain in
                Label(domain, systemImage: "globe")
            }
            .onDelete { offsets in
                domains.remove(atOffsets: offsets)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.suggestedDomains, id: \.domain) { item in
                        let added = domains.contains(item.domain)
                        Button {
                            if added {
                                domains.removeAll { $0 == item.domain }
                            } else {
                                add(domain: item.domain)
                            }
                        } label: {
                            Label(item.name, systemImage: added ? "checkmark" : "plus")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(added ? Color.accentColor : Color(.systemGray5))
                                .foregroundStyle(added ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Websites")
        } footer: {
            Text("Blocked in Safari and other browsers on this iPhone only. If a site is already open in Safari, close Safari for the block to take effect. Up to \(BlockingService.maxDomains) sites.")
        }
    }

    private var durationSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(presets, id: \.seconds) { preset in
                        Button {
                            duration = preset.seconds
                            showCustomPicker = false
                        } label: {
                            Text(preset.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    duration == preset.seconds && !showCustomPicker
                                        ? Color.accentColor
                                        : Color(.systemGray5)
                                )
                                .foregroundStyle(
                                    duration == preset.seconds && !showCustomPicker
                                        ? .white
                                        : .primary
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showCustomPicker = true
                    } label: {
                        Text("Custom")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(showCustomPicker ? Color.accentColor : Color(.systemGray5))
                            .foregroundStyle(showCustomPicker ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            if showCustomPicker {
                HStack {
                    Picker("Hours", selection: $customHours) {
                        ForEach(0...maxCustomHours, id: \.self) { Text("\($0)h").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)

                    Picker("Minutes", selection: $customMinutes) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                            Text("\($0)m").tag($0)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 100)
                }
                .frame(maxWidth: .infinity)
                .onChange(of: customHours) { _, _ in updateCustomDuration() }
                .onChange(of: customMinutes) { _, _ in updateCustomDuration() }
            }
        } header: {
            Text("How long")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Block for \(durationText)")
                    .font(.subheadline.weight(.semibold))
                if isFirstBlock {
                    Text("Your first block is capped at 4 hours. There is no undo, so it is worth finding out what one feels like before committing a day to it. The cap lifts after this one.")
                }
            }
        }
    }

    /// Leads to the confirmation screen rather than starting the block. The
    /// hold-to-lock now lives there, so nothing can be locked without the user
    /// having seen the full list of what it covers (REL-9).
    private var confirmBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Once it starts, nothing in this app can stop it before \(endTimeText).")
                .font(ProsperFont.insight)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showConfirmation = true
            } label: {
                Text("Review what gets locked")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func updateCustomDuration() {
        duration = TimeInterval(customHours * 3600 + customMinutes * 60)
        if duration == 0 { duration = 300 }
        clampDuration()
    }

    /// Keeps the duration inside the cap — a Quick Block preset can arrive
    /// longer than a first-timer is allowed.
    private func clampDuration() {
        if duration > maxDuration {
            duration = maxDuration
            customHours = min(customHours, maxCustomHours)
        }
    }

    private func loadSavedDomains() {
        guard domains.isEmpty else { return }
        domains = UserSettings.current(context: modelContext).savedBlockDomains
    }

    private func addTypedDomain() {
        guard let domain = BlockDomain.normalize(domainInput) else {
            domainError = "Enter a website like reddit.com"
            return
        }
        add(domain: domain)
        domainInput = ""
        domainFieldFocused = true
    }

    private func add(domain: String) {
        domainError = nil
        guard !domains.contains(domain) else { return }
        guard domains.count < BlockingService.maxDomains else {
            domainError = "You can block up to \(BlockingService.maxDomains) websites at once"
            return
        }
        domains.append(domain)
    }

    private func startBlock() {
        guard !BlockingService.shared.hasActiveBlock else { return }

        let settings = UserSettings.current(context: modelContext)
        settings.savedBlockDomains = domains
        try? modelContext.save()

        BlockingService.shared.startBlock(
            apps: selection.applicationTokens,
            webDomains: selection.webDomainTokens,
            domains: domains,
            duration: duration,
            selection: selection
        )
        dismiss()
    }
}
