import SwiftUI
import SwiftData
import FamilyControls
import ManagedSettings
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
    /// Apple's list, open to hand the app every app (and the websites iOS
    /// offers) so each can be labelled here with one tap (UX-31).
    @State private var showingAllApps = false
    @State private var pickedApps = FamilyActivitySelection(includeEntireCategory: true)
    /// Every app and website token the app has been given, in a stable order
    /// fixed when the screen opens, unlabelled first. Labelling one does not
    /// make the list jump.
    @State private var appOrder: [ApplicationToken] = []
    @State private var webOrder: [WebDomainToken] = []
    enum Tab: Hashable { case label, day }
    @State private var tab: Tab = .label
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
                options: [(.label, "Label"), (.day, "Where it went")],
                selection: $tab
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            switch tab {
            case .label: labelPage
            case .day: dayPage
            }
        }
        .background(ProsperColor.background)
        .navigationTitle("Label your day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .familyActivityPicker(
            headerText: "Tick every category you use. Stolen Glance lists those apps here to label. Nothing gets blocked.",
            isPresented: $showingAllApps,
            selection: $pickedApps
        )
        .onChange(of: showingAllApps) { _, open in
            if !open { takePickedApps() }
        }
        .tracksReportDay($reportDay)
        .onAppear(perform: loadIfNeeded)
        .offeringNewSitesToSchedules($sitesForSchedules)
    }

    // MARK: - Where it went

    private var dayPage: some View {
        VStack(spacing: 0) {
            AuroraSegmented(
                options: [(.day, "Today"), (.week, "Last 7 days")],
                selection: $range
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            UsageReportView(
                filter: range == .day ? UsageReportFilter.today() : UsageReportFilter.lastSevenDays(),
                context: .dayLedger
            )
            .id("ledger-\(range)-\(revision)-\(Int(reportDay.timeIntervalSince1970))")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Label: every app and site, one tap each

    private enum Anchor: Hashable { case apps, sites }

    private var labelPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        jumpChip("Apps", systemImage: "square.grid.2x2") { proxy.scrollTo(Anchor.apps, anchor: .top) }
                        jumpChip("Websites", systemImage: "globe") { proxy.scrollTo(Anchor.sites, anchor: .top) }
                        Spacer(minLength: 0)
                    }
                    appsSection.id(Anchor.apps)
                    sitesSection.id(Anchor.sites)
                    Text("Distracting apps and sites join your block list and count toward warnings. iOS can't time a typed site, so sites change the day's balance but not warnings.")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }

    private func jumpChip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy(duration: 0.3)) { action() } }) {
            Label(title, systemImage: systemImage)
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(ProsperColor.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(ProsperColor.line, lineWidth: 1))
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: Apps

    private var appsSection: some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apps").labelCaps()
                    Spacer()
                    if !appOrder.isEmpty {
                        Button("Add apps") { showingAllApps = true }
                            .scaledFont(13, weight: .semibold)
                            .foregroundStyle(ProsperColor.accent)
                    }
                }
                if appOrder.isEmpty {
                    allAppsPrompt
                } else {
                    Text("Unlabelled first. iOS keeps app names from Stolen Glance, so it can't sort them by use.")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(appOrder, id: \.self) { token in
                        labelRow(current: appClass(token)) {
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .scaledFont(15, weight: .medium)
                                .foregroundStyle(ProsperColor.ink)
                                .lineLimit(1)
                        } onSelect: { setApp(token, to: $0) }
                        if token != appOrder.last {
                            Divider().overlay(ProsperColor.line)
                        }
                    }
                }
            }
        }
    }

    /// The one-time step: iOS only hands an app the apps a person picks in
    /// Apple's list, so the list has to be opened once with every category.
    private var allAppsPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("See every app here, then label each with one tap.")
                .scaledFont(17, weight: .semibold)
                .foregroundStyle(ProsperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Once, in Apple's list, tick every category you use and tap Done. Nothing gets blocked.")
                .scaledFont(14)
                .foregroundStyle(ProsperColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingAllApps = true
            } label: {
                Label("Show my apps", systemImage: "square.grid.2x2")
            }
            .buttonStyle(AuroraButtonStyle())
        }
        .padding(.top, 6)
    }

    // MARK: Websites

    @State private var siteInput = ""
    @State private var siteError: String?

    private var sitesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Websites").labelCaps()
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
                    Text("A site you add starts as Distracting. Tap another label to change it; press and hold to remove it.")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(taggedSites, id: \.domain) { entry in
                        siteRow(entry.domain, current: entry.cls)
                    }
                    ForEach(webOrder, id: \.self) { token in
                        labelRow(current: webClass(token)) {
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .scaledFont(15)
                                .foregroundStyle(ProsperColor.ink)
                                .lineLimit(1)
                        } onSelect: { setWeb(token, to: $0) }
                    }
                }
            }
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
                            Divider().overlay(ProsperColor.line)
                        }
                    }
                }
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

    /// The current book of labels, from this screen's state.
    private var book: LabelBook {
        var book = LabelBook()
        book.productive = productive
        book.distracting = distracting
        book.rest = rest
        book.productiveDomains = productiveDomains
        book.distractingDomains = distractingDomains
        book.restDomains = restDomains
        return book
    }

    private func take(_ book: LabelBook) {
        productive = book.productive
        distracting = book.distracting
        rest = book.rest
        productiveDomains = book.productiveDomains
        distractingDomains = book.distractingDomains
        restDomains = book.restDomains
        persist()
    }

    private func appClass(_ token: ApplicationToken) -> TimeClass? {
        if distracting.applicationTokens.contains(token) { return .distracting }
        if rest.applicationTokens.contains(token) { return .rest }
        if productive.applicationTokens.contains(token) { return .productive }
        return nil
    }

    private func webClass(_ token: WebDomainToken) -> TimeClass? {
        if distracting.webDomainTokens.contains(token) { return .distracting }
        if rest.webDomainTokens.contains(token) { return .rest }
        if productive.webDomainTokens.contains(token) { return .productive }
        return nil
    }

    private func setApp(_ token: ApplicationToken, to label: TimeClass) {
        var next = book
        next.assign(label, to: .app(token, name: ""))
        take(next)
    }

    private func setWeb(_ token: WebDomainToken, to label: TimeClass) {
        var next = book
        next.assign(label, to: .web(token))
        take(next)
    }

    /// What Apple's list handed over joins the apps and sites listed here.
    /// Picking them labels nothing.
    private func takePickedApps() {
        guard !pickedApps.applicationTokens.isEmpty || !pickedApps.webDomainTokens.isEmpty else { return }
        LabelStore.remember(pickedApps)
        pickedApps = FamilyActivitySelection(includeEntireCategory: true)
        orderItems()
    }

    /// Unlabelled first, then the rest; a stable order within each, so the
    /// list holds still while labels are given.
    private func orderItems() {
        let known = LabelStore.knownItems(adding: [productive, distracting, rest])
        func key<T: Encodable>(_ token: T) -> String {
            (try? JSONEncoder().encode(token)).map { $0.base64EncodedString() } ?? ""
        }
        appOrder = known.applicationTokens.sorted { a, b in
            let la = appClass(a) == nil, lb = appClass(b) == nil
            return la != lb ? la : key(a) < key(b)
        }
        webOrder = known.webDomainTokens.sorted { a, b in
            let la = webClass(a) == nil, lb = webClass(b) == nil
            return la != lb ? la : key(a) < key(b)
        }
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
        orderItems()
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
