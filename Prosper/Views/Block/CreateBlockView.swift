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
    @State private var showConfirmation: Bool

    /// Prefill hook for Quick Block presets: seed the sheet with the user's
    /// waste selection + typed domains and a chosen duration, then jump
    /// straight to the confirmation alert. `nil` = manual entry.
    init(prefill: BlockPrefill? = nil) {
        _selection = State(initialValue: prefill?.selection ?? FamilyActivitySelection())
        _domains = State(initialValue: prefill?.domains ?? [])
        _duration = State(initialValue: prefill?.duration ?? 3600)
        _showConfirmation = State(initialValue: prefill != nil)
    }

    private let presets: [(label: String, seconds: TimeInterval)] = [
        ("30m", 1800),
        ("1h", 3600),
        ("2h", 7200),
        ("4h", 14400),
        ("8h", 28800),
    ]

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
        !selection.applicationTokens.isEmpty || siteCount > 0
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
                if hasSelection {
                    confirmSection
                }
            }
            .navigationTitle("New Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .alert("Start Block?", isPresented: $showConfirmation) {
                Button("Start Block", role: .destructive) {
                    startBlock()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Block \(selection.applicationTokens.count) app(s) and \(siteCount) site(s) for \(durationText).\n\n⚠️ This CANNOT be undone. You will not be able to access these apps and sites until the block expires.")
            }
            .onAppear(perform: loadSavedDomains)
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
                        ForEach(0..<24) { Text("\($0)h").tag($0) }
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
            Text("Block for \(durationText)")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var confirmSection: some View {
        Section {
            Button {
                showConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Start Block", systemImage: "lock.fill")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .tint(.red)
        } footer: {
            Text("Once started, this block cannot be cancelled or shortened.")
                .foregroundStyle(.red)
        }
    }

    private func updateCustomDuration() {
        duration = TimeInterval(customHours * 3600 + customMinutes * 60)
        if duration == 0 { duration = 300 }
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
