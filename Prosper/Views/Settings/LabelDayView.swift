import SwiftUI
import SwiftData
import FamilyControls
import DeviceActivity

/// Label your day (UX-29, replacing the UX-17 classification editor): the
/// hours of the day on top, filed under their labels, and the labels to give
/// underneath.
///
/// Three realities from iOS shape it:
/// * Only the report extension can see per-app time, and it cannot hand a tap
///   back to the app. So the list is for reading, and the label buttons sit
///   under it, in the app.
/// * Apps can only be chosen in Apple's own picker. A label button opens it
///   for that label, with what already carries the label ticked.
/// * Websites and platforms are plain names, so they get a one-tap menu.
///
/// "Distracting" is the block list, so labelling something Distracting also
/// puts it on the Lock tab's list and under warnings. Anything unlabelled
/// stays unlabelled; nothing is assumed productive (UX-9). An app, category
/// or site carries one label at a time: giving it a new one takes it out of
/// the old one.
///
/// Platform labels and typed sites feed the day's balance and the block list,
/// but iOS can only time what its picker hands out, so they never count
/// toward warnings (QA-9).
struct LabelDayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Range: Hashable { case day, week }
    @State private var range: Range = .day

    @State private var productive = FamilyActivitySelection()
    @State private var distracting = FamilyActivitySelection()
    @State private var rest = FamilyActivitySelection()
    @State private var productiveDomains: [String] = []
    @State private var distractingDomains: [String] = []
    @State private var restDomains: [String] = []
    /// Waste sites just added that some schedule lacks (UX-26).
    @State private var sitesForSchedules: [String] = []
    @State private var activePicker: TimeClass?
    @State private var showSites = false
    @State private var loaded = false
    /// Bumped on every saved change, so the hosted list is rebuilt from the
    /// new labels instead of iOS's cached copy (see DashboardView).
    @State private var revision = 0
    @State private var reportDay = Calendar.current.startOfDay(for: .now)

    static let labels: [TimeClass] = [.distracting, .productive, .rest]

    /// Presenter supplies navigation: Settings pushes this in its own stack,
    /// Today and Insights wrap it in a NavigationStack sheet.
    var body: some View {
        VStack(spacing: 0) {
            AuroraSegmented(
                options: [(.day, "Today"), (.week, "Last 7 days")],
                selection: $range
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            UsageReportView(
                filter: range == .day ? UsageReportFilter.today() : UsageReportFilter.lastSevenDays(),
                context: .dayLedger
            )
            .id("ledger-\(range)-\(revision)-\(Int(reportDay.timeIntervalSince1970))")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { labelBar }
        .background(ProsperColor.background)
        .navigationTitle("Where your time went")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .familyActivityPicker(
            headerText: activePicker.map { "Tick everything that is \($0.ledgerTitle.lowercased()) for you." },
            isPresented: Binding(get: { activePicker != nil }, set: { if !$0 { activePicker = nil } }),
            selection: activeSelectionBinding
        )
        .sheet(isPresented: $showSites) {
            NavigationStack { sitesScreen }
        }
        .tracksReportDay($reportDay)
        .onAppear(perform: loadIfNeeded)
        .offeringNewSitesToSchedules($sitesForSchedules)
        // Rows above link to the one-tap label sheet; this screen is a sheet
        // itself, so it presents that one.
        .quickLabelSheet(isOverlay: true)
        .onChange(of: QuickLabelRouter.shared.revision) { _, _ in reload() }
    }

    // MARK: - Label buttons

    private var labelBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Label many apps at once").labelCaps()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { labelButtons }
                VStack(spacing: 8) { labelButtons }
            }
            Button {
                showSites = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(ProsperColor.accent)
                    Text("Label websites and platforms")
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(ProsperColor.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ProsperColor.ink2)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(ProsperColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Tap any app or site above to label it. To label many apps at once, tap a label and tick them in Apple's list.")
                .scaledFont(12)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    @ViewBuilder
    private var labelButtons: some View {
        ForEach(Self.labels, id: \.self) { label in
            let count = appCount(label)
            Button {
                activePicker = label
            } label: {
                HStack(spacing: 7) {
                    Circle().fill(label.color).frame(width: 9, height: 9)
                    Text(label.ledgerTitle)
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(ProsperColor.ink)
                        .lineLimit(1)
                    if count > 0 {
                        Text("\(count)")
                            .scaledFont(13, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(label.color)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(label.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(label.color.opacity(0.5), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Label apps as \(label.ledgerTitle.lowercased())")
            .accessibilityValue(count == 0 ? "None yet" : "\(count) chosen")
            .accessibilityHint("Opens Apple's app list")
        }
    }

    private func appCount(_ label: TimeClass) -> Int {
        let chosen = selection(for: label)
        return chosen.applicationTokens.count + chosen.categoryTokens.count
    }

    // MARK: - Websites and platforms

    @State private var siteInput = ""
    @State private var siteError: String?

    private var sitesScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Platforms").labelCaps()
                        Text("One label covers every way you reach it: the app and all its websites.")
                            .scaledFont(13)
                            .foregroundStyle(ProsperColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                        ForEach(PlatformCatalog.all) { platform in
                            platformRow(platform)
                            if platform.id != PlatformCatalog.all.last?.id {
                                Divider().overlay(ProsperColor.line).padding(.leading, 46)
                            }
                        }
                    }
                }
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Other sites").labelCaps()
                        HStack(spacing: 8) {
                            TextField("Add a site, like news.com", text: $siteInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .submitLabel(.done)
                                .scaledFont(15)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(ProsperColor.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onSubmit(addSite)
                            Button("Add", action: addSite)
                                .scaledFont(15, weight: .semibold)
                                .disabled(siteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let siteError {
                            Text(siteError)
                                .scaledFont(13)
                                .foregroundStyle(ProsperColor.distracting)
                        }
                        if taggedSites.isEmpty {
                            Text("A site you add starts as Distracting. Change it with its label.")
                                .scaledFont(13)
                                .foregroundStyle(ProsperColor.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(taggedSites, id: \.domain) { entry in
                                siteRow(entry.domain, current: entry.cls)
                            }
                        }
                    }
                }
                Text("Distracting sites join your block list. iOS can't time a typed site, so sites change the day's balance but not warnings.")
                    .scaledFont(12)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(ProsperColor.background)
        .navigationTitle("Websites and platforms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showSites = false }
            }
        }
    }

    private func platformRow(_ platform: Platform) -> some View {
        let chosen = platformClass(platform)
        return HStack(spacing: 12) {
            BrandMark(platform: platform, size: 34)
            Text(platform.name)
                .scaledFont(15, weight: .medium)
                .foregroundStyle(ProsperColor.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            LabelMenu(
                // What the day is actually filed under: the person's own
                // label, or the built-in one for the obvious cases (UX-20).
                current: chosen ?? platform.defaultClass.map { TimeClass($0) },
                // A built-in label cannot be cleared, only replaced.
                clearTitle: chosen != nil && platform.defaultClass == nil ? "No label" : nil
            ) { setPlatform(platform, to: $0) }
        }
        .frame(minHeight: 48)
    }

    private func siteRow(_ domain: String, current: TimeClass) -> some View {
        HStack(spacing: 12) {
            SiteIcon(domain: domain, size: 34)
            Text(domain)
                .scaledFont(15)
                .foregroundStyle(ProsperColor.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            LabelMenu(current: current, clearTitle: "Remove site") { label in
                if let label { setClass(domain: domain, to: label) } else { removeDomain(domain) }
            }
        }
        .frame(minHeight: 48)
    }

    // MARK: - Website model helpers

    private struct SiteEntry { let domain: String; let cls: TimeClass }

    /// Custom tagged sites with their class, distracting first, then productive,
    /// rest. Hosts owned by a catalog platform are hidden here — the Platforms
    /// card is their home, so they don't show up twice.
    private var taggedSites: [SiteEntry] {
        let entries = distractingDomains.map { SiteEntry(domain: $0, cls: .distracting) }
            + productiveDomains.map { SiteEntry(domain: $0, cls: .productive) }
            + restDomains.map { SiteEntry(domain: $0, cls: .rest) }
        return entries.filter { !PlatformCatalog.allDomains.contains($0.domain.lowercased()) }
    }

    private func classOf(domain: String) -> TimeClass? {
        // Distracting > rest > productive, matching the report's resolution (QA-1).
        if distractingDomains.contains(domain) { return .distracting }
        if restDomains.contains(domain) { return .rest }
        if productiveDomains.contains(domain) { return .productive }
        return nil
    }

    /// A platform's own label, read from its primary domain (all its domains
    /// move together, so the first one represents the group).
    private func platformClass(_ platform: Platform) -> TimeClass? {
        classOf(domain: platform.primaryDomain)
    }

    /// Move every host of a platform into one class at once — or, when `c` is
    /// nil, remove them all. Keeps the three domain lists exclusive so a platform
    /// is never half-productive, half-distracting.
    private func setPlatform(_ platform: Platform, to c: TimeClass?) {
        for domain in platform.domains { clear(domain) }
        if let c {
            for domain in platform.domains { file(domain, under: c) }
        }
        persist()
    }

    private func addSite() {
        guard let normalized = BlockDomain.normalize(siteInput) else {
            siteError = "Type the full address, like news.com."
            return
        }
        siteError = nil
        siteInput = ""
        if classOf(domain: normalized) == nil { setClass(domain: normalized, to: .distracting) }
    }

    private func setClass(domain: String, to c: TimeClass) {
        clear(domain)
        file(domain, under: c)
        persist()
    }

    private func removeDomain(_ domain: String) {
        clear(domain)
        persist()
    }

    private func clear(_ domain: String) {
        productiveDomains.removeAll { $0 == domain }
        distractingDomains.removeAll { $0 == domain }
        restDomains.removeAll { $0 == domain }
    }

    private func file(_ domain: String, under c: TimeClass) {
        switch c {
        case .productive: productiveDomains.append(domain)
        case .distracting: distractingDomains.append(domain)
        case .rest: restDomains.append(domain)
        case .unclassified: break
        }
    }

    // MARK: - App selection bindings

    /// The picker edits one label's apps. Whatever it gains is taken out of
    /// the other two, so the label just given is the one that counts.
    private var activeSelectionBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { activePicker.map { selection(for: $0) } ?? FamilyActivitySelection() },
            set: { newValue in
                guard let label = activePicker else { return }
                let added = LabelSets.added(in: newValue, since: selection(for: label))
                setSelection(newValue, for: label)
                for other in Self.labels where other != label {
                    setSelection(LabelSets.removing(added, from: selection(for: other)), for: other)
                }
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
        var book = LabelBook()
        book.productive = productive
        book.distracting = distracting
        book.rest = rest
        book.productiveDomains = productiveDomains
        book.distractingDomains = distractingDomains
        book.restDomains = restDomains
        let offer = LabelStore.save(book, context: modelContext)
        if !offer.isEmpty { sitesForSchedules = offer }
        revision += 1
    }

    /// A row labelled through the one-tap sheet: take the saved labels back in.
    private func reload() {
        loaded = false
        loadIfNeeded()
        revision += 1
    }
}

/// The label on a website or platform row: says what it is now, in words,
/// and opens the three choices.
private struct LabelMenu: View {
    let current: TimeClass?
    /// The extra, last choice ("No label", "Remove site"); nil hides it.
    var clearTitle: String?
    let onSelect: (TimeClass?) -> Void

    private var tint: Color { current?.color ?? ProsperColor.accent }

    var body: some View {
        Menu {
            ForEach(LabelDayView.labels, id: \.self) { label in
                Button {
                    onSelect(label)
                } label: {
                    if label == current {
                        Label(label.ledgerTitle, systemImage: "checkmark")
                    } else {
                        Text(label.ledgerTitle)
                    }
                }
            }
            if let clearTitle {
                Divider()
                Button(clearTitle, role: .destructive) { onSelect(nil) }
            }
        } label: {
            HStack(spacing: 6) {
                if current != nil {
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
                Text(current?.ledgerTitle ?? "Label")
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(current == nil ? ProsperColor.accent : ProsperColor.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProsperColor.ink2)
            }
            // The label keeps its width; a long name beside it shortens instead.
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Label")
        .accessibilityValue(current?.ledgerTitle ?? "None")
    }
}
