import SwiftUI
import FamilyControls

struct CreateBlockView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection = FamilyActivitySelection()
    @State private var isPickerPresented = false
    @State private var duration: TimeInterval = 3600
    @State private var showCustomPicker = false
    @State private var customHours = 1
    @State private var customMinutes = 0
    @State private var showConfirmation = false

    private let presets: [(label: String, seconds: TimeInterval)] = [
        ("30m", 1800),
        ("1h", 3600),
        ("2h", 7200),
        ("4h", 14400),
        ("8h", 28800),
    ]

    private var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty
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
                Text("Block \(selection.applicationTokens.count) app(s) and \(selection.webDomainTokens.count) site(s) for \(durationText).\n\n⚠️ This CANNOT be undone. You will not be able to access these apps until the block expires.")
            }
        }
    }

    private var appsSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack {
                    Label("Select Apps & Sites", systemImage: "apps.iphone")
                    Spacer()
                    if hasSelection {
                        Text("\(selection.applicationTokens.count + selection.webDomainTokens.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("What to block")
        } footer: {
            if hasSelection {
                Text("\(selection.applicationTokens.count) app(s), \(selection.webDomainTokens.count) website(s) selected")
            }
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

    private func startBlock() {
        BlockingService.shared.startBlock(
            apps: selection.applicationTokens,
            webDomains: selection.webDomainTokens,
            duration: duration
        )
        dismiss()
    }
}
