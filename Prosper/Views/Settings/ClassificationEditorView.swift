import SwiftUI
import SwiftData
import FamilyControls
import DeviceActivity

/// UX-17 — the classification triage. Goal: tag your biggest time-sinks fast.
///
/// Three realities from iOS shape the layout:
/// * Only the report extension can rank your usage, and its view is display-only
///   — so the "Where your time goes" list at the top is a *guide*, not tappable.
/// * `FamilyActivitySelection` app tokens are get-only, so apps can only be added
///   or removed inside Apple's system picker (one picker per class).
/// * Websites are plain strings we fully control, so they get the neat one-tap
///   Productive / Distracting / Rest control and quick-pick chips.
///
/// "Distracting" is the existing waste list, so warnings and quick-block presets
/// keep working. Anything unlisted stays Unclassified (UX-9). Every change syncs
/// to the App Group so Today's balance updates.
struct ClassificationEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var productive = FamilyActivitySelection()
    @State private var distracting = FamilyActivitySelection()
    @State private var rest = FamilyActivitySelection()
    @State private var productiveDomains: [String] = []
    @State private var distractingDomains: [String] = []
    @State private var restDomains: [String] = []
    @State private var siteInput = ""
    @State private var activePicker: TimeClass?
    @State private var showUsage = true
    @State private var loaded = false

    /// One-tap suggestions of the usual time-sinks (the set the user chose).
    private let commonSites = ["youtube.com", "facebook.com", "instagram.com",
                               "tiktok.com", "reddit.com", "x.com", "netflix.com"]

    private let appClasses: [TimeClass] = [.distracting, .productive, .rest]

    /// Presenter supplies navigation: Settings pushes this in its own stack, the
    /// Today CTA wraps it in a NavigationStack sheet. No inner stack (nesting one
    /// inside a NavigationLink push swallows the push).
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                usageReference
                appsSection
                websitesSection
            }
            .padding(20)
        }
        .background(ProsperColor.background)
        .navigationTitle("Classify your time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .familyActivityPicker(
            isPresented: Binding(get: { activePicker != nil }, set: { if !$0 { activePicker = nil } }),
            selection: activeSelectionBinding
        )
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Intro

    private var intro: some View {
        Text("Tell Prosper what each app and site means to you. Start with your biggest time-sinks below. Anything you don't classify stays Unclassified — nothing is assumed productive.")
            .font(.system(size: 13))
            .foregroundStyle(ProsperColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Usage reference (guide, not interactive)

    private var usageReference: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showUsage.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Where your time goes").labelCaps()
                            Text("Last 7 days · tag the biggest first")
                                .font(.system(size: 12))
                                .foregroundStyle(ProsperColor.ink2)
                        }
                        Spacer()
                        Image(systemName: showUsage ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ProsperColor.accent)
                    }
                }
                .buttonStyle(.plain)

                if showUsage {
                    UsageReportView(filter: UsageReportFilter.lastSevenDays(), context: .usageSummary)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .allowsHitTesting(false) // read-only guide; its inner ScrollView must not steal taps from the cards below
                }
            }
        }
    }

    // MARK: - Apps (system picker per class)

    private var appsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Apps").labelCaps()
                Text("Apple only lets you choose apps in its own picker, so pick per class. Tap a class to add or remove its apps.")
                    .font(.system(size: 12))
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(appClasses, id: \.self) { c in
                    appClassRow(c)
                    if c != appClasses.last { Divider().overlay(ProsperColor.line) }
                }
            }
        }
    }

    @ViewBuilder
    private func appClassRow(_ c: TimeClass) -> some View {
        let sel = selection(for: c)
        VStack(alignment: .leading, spacing: 8) {
            Button { activePicker = c } label: {
                HStack(spacing: 9) {
                    Circle().fill(c.color).frame(width: 9, height: 9)
                    Text(c.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProsperColor.ink)
                    Spacer()
                    let count = sel.applicationTokens.count + sel.categoryTokens.count
                    Text(count == 0 ? "Add" : "\(count) · Edit")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ProsperColor.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ProsperColor.accent)
                }
            }
            .buttonStyle(.plain)
            if !sel.applicationTokens.isEmpty || !sel.categoryTokens.isEmpty {
                SelectionChips(selection: sel,
                               placeholderCount: sel.applicationTokens.count + sel.categoryTokens.count)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Websites (unified one-tap tagging)

    private var websitesSection: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Websites").labelCaps()

                // Quick-pick common time-sinks.
                FlowLayout(spacing: 8) {
                    ForEach(commonSites, id: \.self) { site in
                        quickChip(site)
                    }
                }

                // Add a custom site.
                HStack(spacing: 8) {
                    TextField("Add a site, e.g. news.com", text: $siteInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(size: 15))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(ProsperColor.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onSubmit { addSite() }
                    Button("Add") { addSite() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(siteInput.trimmingCharacters(in: .whitespaces).isEmpty ? ProsperColor.ink2 : ProsperColor.accent)
                        .disabled(siteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Tagged sites, distracting first.
                if taggedSites.isEmpty {
                    Text("No sites tagged yet. Tap a suggestion above to start.")
                        .font(.system(size: 12))
                        .foregroundStyle(ProsperColor.ink2)
                } else {
                    VStack(spacing: 10) {
                        ForEach(taggedSites, id: \.domain) { entry in
                            siteRow(entry.domain, current: entry.cls)
                        }
                    }
                }
            }
        }
    }

    private func quickChip(_ site: String) -> some View {
        let added = classOf(domain: site) != nil
        return Button {
            if !added { setClass(domain: site, to: .distracting) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(site).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(added ? ProsperColor.distracting : ProsperColor.ink)
            .padding(.vertical, 7)
            .padding(.horizontal, 11)
            .background(added ? ProsperColor.distracting.opacity(0.12) : ProsperColor.surface2)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    private func siteRow(_ domain: String, current: TimeClass) -> some View {
        HStack(spacing: 10) {
            Circle().fill(current.color).frame(width: 8, height: 8)
            Text(domain)
                .font(.system(size: 14))
                .foregroundStyle(ProsperColor.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            ClassSegments(current: current) { setClass(domain: domain, to: $0) }
            Button { removeDomain(domain) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ProsperColor.ink2)
                    .frame(width: 24, height: 24)
                    .background(ProsperColor.surface2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Website model helpers

    private struct SiteEntry { let domain: String; let cls: TimeClass }

    /// Every tagged site with its class, distracting first, then productive, rest.
    private var taggedSites: [SiteEntry] {
        distractingDomains.map { SiteEntry(domain: $0, cls: .distracting) }
        + productiveDomains.map { SiteEntry(domain: $0, cls: .productive) }
        + restDomains.map { SiteEntry(domain: $0, cls: .rest) }
    }

    private func classOf(domain: String) -> TimeClass? {
        if distractingDomains.contains(domain) { return .distracting }
        if productiveDomains.contains(domain) { return .productive }
        if restDomains.contains(domain) { return .rest }
        return nil
    }

    private func addSite() {
        guard let normalized = BlockDomain.normalize(siteInput) else { return }
        siteInput = ""
        if classOf(domain: normalized) == nil { setClass(domain: normalized, to: .distracting) }
    }

    private func setClass(domain: String, to c: TimeClass) {
        productiveDomains.removeAll { $0 == domain }
        distractingDomains.removeAll { $0 == domain }
        restDomains.removeAll { $0 == domain }
        switch c {
        case .productive: productiveDomains.append(domain)
        case .distracting: distractingDomains.append(domain)
        case .rest: restDomains.append(domain)
        case .unclassified: break
        }
        persist()
    }

    private func removeDomain(_ domain: String) {
        productiveDomains.removeAll { $0 == domain }
        distractingDomains.removeAll { $0 == domain }
        restDomains.removeAll { $0 == domain }
        persist()
    }

    // MARK: - App selection bindings

    private var activeSelectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { activePicker.map { selection(for: $0) } ?? FamilyActivitySelection() },
            set: { newValue in
                guard let c = activePicker else { return }
                setSelection(newValue, for: c)
                persist()
            }
        )
    }

    private func selection(for c: TimeClass) -> FamilyActivitySelection {
        switch c {
        case .productive: return productive
        case .distracting: return distracting
        case .rest: return rest
        case .unclassified: return FamilyActivitySelection()
        }
    }

    private func setSelection(_ value: FamilyActivitySelection, for c: TimeClass) {
        switch c {
        case .productive: productive = value
        case .distracting: distracting = value
        case .rest: rest = value
        case .unclassified: break
        }
    }

    // MARK: - Card container

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ProsperColor.line, lineWidth: 1)
                    .allowsHitTesting(false) // don't let the border swallow taps on the controls inside
            }
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let s = UserSettings.current(context: modelContext)
        productive = WasteSelectionCodec.decode(s.productiveSelectionData)
        distracting = WasteSelectionCodec.decode(s.wasteAppSelectionData)   // waste == distracting
        rest = WasteSelectionCodec.decode(s.restSelectionData)
        productiveDomains = s.productiveDomains
        distractingDomains = s.wasteDomains
        restDomains = s.restDomains
    }

    private func persist() {
        let s = UserSettings.current(context: modelContext)
        s.productiveSelectionData = WasteSelectionCodec.encode(productive)
        s.productiveDomains = productiveDomains
        s.restSelectionData = WasteSelectionCodec.encode(rest)
        s.restDomains = restDomains
        // Distracting is the waste list.
        s.wasteAppSelectionData = WasteSelectionCodec.encode(distracting)
        s.wasteAppCount = distracting.applicationTokens.count + distracting.categoryTokens.count
        s.wasteDomains = distractingDomains
        try? modelContext.save()
        s.syncClassificationSnapshot()

        WarningService.shared.refreshSchedule(
            enabled: s.warningsEnabled,
            selection: distracting,
            typedDomains: distractingDomains,
            thresholdMinutes: s.wasteWarningThresholdMinutes
        )
    }
}

/// The one-tap Productive / Distracting / Rest control on a website row.
private struct ClassSegments: View {
    let current: TimeClass
    let onSelect: (TimeClass) -> Void

    private let classes: [TimeClass] = [.productive, .distracting, .rest]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(classes, id: \.self) { c in
                let selected = c == current
                Button { onSelect(c) } label: {
                    Text(letter(c))
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(selected ? .white : c.color)
                        .background(selected ? c.color : c.color.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.label)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    private func letter(_ c: TimeClass) -> String {
        switch c {
        case .productive: return "P"
        case .distracting: return "D"
        case .rest: return "R"
        case .unclassified: return "?"
        }
    }
}
