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

    }

    // MARK: - Label buttons

    private var labelBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Label apps as").labelCaps()
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
            Text("Tap a label, then tick its apps in Apple's list; it has a search field. Websites and platforms take one tap each.")
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
                            Text("A site you add starts as Distracting. Tap another label to change it; press and hold to remove it.")
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

    /// A platform: its mark, its name, and its three labels as chips, one
    /// tap each. A long press offers "No label" when it has no usual one.
    private func platformRow(_ platform: Platform) -> some View {
        let chosen = platformClass(platform)
        // What the day is filed under: the person's own label, or the
        // built-in one for the obvious cases (UX-20).
        let shown = chosen ?? platform.defaultClass.map { TimeClass($0) }
        return labelRow(current: shown) {
            BrandMark(platform: platform, size: 34)
            Text(platform.name)
                .scaledFont(15, weight: .medium)
                .foregroundStyle(ProsperColor.ink)
                .lineLimit(1)
        } onSelect: { setPlatform(platform, to: $0) }
        .contextMenu {
            // A built-in label cannot be cleared, only replaced.
            if chosen != nil, platform.defaultClass == nil {
                Button("No label") { setPlatform(platform, to: nil) }
            }
        }
    }

    private func siteRow(_ domain: String, current: TimeClass) -> some View {
        labelRow(current: current) {
            SiteIcon(domain: domain, size: 34)
            Text(domain)
                .scaledFont(15)
                .foregroundStyle(ProsperColor.ink)
                .lineLimit(1)
        } onSelect: { setClass(domain: domain, to: $0) }
        .contextMenu {
            Button("Remove site", role: .destructive) { removeDomain(domain) }
        }
    }

    private func labelRow<Title: View>(
        current: TimeClass?,
        @ViewBuilder title: () -> Title,
        onSelect: @escaping (TimeClass) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) { title() }
            LabelChips(current: current, onSelect: onSelect)
        }
        .padding(.vertical, 8)
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
}

/// The three labels as chips, one tap each (UX-31). The chosen one's tint
/// slides across to a new choice, the way Superlist's list pill morphs into
/// the one picked (60fps.design/shots/superlist-task-to-list-switch). No
/// slide under Reduce Motion.
private struct LabelChips: View {
    let current: TimeClass?
    let onSelect: (TimeClass) -> Void

    @Namespace private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(LabelDayView.labels, id: \.self) { label in
            let selected = label == current
            Button {
                guard !selected else { return }
                taps += 1
                withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.22)) {
                    onSelect(label)
                }
            } label: {
                HStack(spacing: 5) {
                    if selected {
                        Image(systemName: "checkmark")
                            .scaledFont(11, weight: .bold)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        Circle().fill(label.color).frame(width: 7, height: 7)
                    }
                    Text(label.shortTitle)
                        .scaledFont(13, weight: .semibold)
                        .lineLimit(1)
                }
                .foregroundStyle(selected ? label.color : ProsperColor.ink2)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background {
                    ZStack {
                        Capsule().fill(ProsperColor.surface2)
                        if selected {
                            Capsule()
                                .fill(label.color.opacity(0.16))
                                .overlay(Capsule().strokeBorder(label.color.opacity(0.55), lineWidth: 1.5))
                                .matchedGeometryEffect(id: "chosen", in: tint)
                        }
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label.shortTitle)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
