import Foundation
import FamilyControls
import ManagedSettings

/// The Adult Content Guard: a permanent, one-way block of adult websites and
/// of any apps the user chooses to put behind it (E9).
///
/// This is a different animal from a block session, and the difference is the
/// product. A session is a timed decision; the guard is the absence of one. A
/// porn urge is short and cue-driven — late, alone, bored, stressed — and it
/// arrives precisely when the part of the brain that makes good decisions is
/// offline. Anything that has to be switched on each evening is a nightly
/// negotiation with that state, and the state wins often enough. So the guard
/// is switched on once, with a clear head, and then it is simply on.
///
/// Rules, in order of importance:
///
/// 1. **There is no off.** This type has no `disable`, `clear` or `remove`,
///    `SharedGuardState` has none, and nothing in the app may grow one. The
///    only way to lift the guard is the way out of every StolenEyes lock:
///    deleting the app (see `LockExitCopy`).
/// 2. **Its own store.** The guard lives in `ManagedSettingsStore(named:
///    "adultContentGuard")`, never the default store that block sessions use.
///    A session ending — in `BlockingService` or in the monitor extension —
///    clears the default store and cannot reach this one. iOS combines stores
///    with the most restrictive setting winning (WWDC22), so a session can
///    only ever add restrictions on top.
/// 3. **Append-only coverage.** Apps and sites can be added later, never taken
///    away. Adding is cheap on purpose: the moment the user finds a gap is the
///    moment to close it, not the moment to wait for a new build.
/// 4. **Re-asserted on launch.** The settings persist on their own, but
///    rewriting them on every launch costs nothing and means an iOS update or
///    a restore that dropped them is healed the next time the app opens.
final class AdultContentGuard: @unchecked Sendable {
    static let shared = AdultContentGuard(
        store: ManagedSettingsStore(named: storeName),
        state: SharedGuardState.appGroup
    )

    nonisolated(unsafe) static let storeName = ManagedSettingsStore.Name("adultContentGuard")

    private let store: AdultContentGuardStore
    private let state: SharedGuardState?

    /// `shared` is the guard. This initialiser exists so the tests can watch
    /// what reaches the store without writing to the simulator's real one.
    init(store: AdultContentGuardStore, state: SharedGuardState?) {
        self.store = store
        self.state = state
    }

    // MARK: - Reading

    var isEnabled: Bool { state?.isEnabled ?? false }

    var enabledAt: Date? { state?.enabledAt }

    /// Everything the picker has put behind the guard so far.
    var selection: FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        guard let state else { return selection }
        selection.applicationTokens = state.applicationTokens
        selection.categoryTokens = state.categoryTokens
        selection.webDomainTokens = state.webDomainTokens
        return selection
    }

    /// Sites the user added by name, on top of `AdultDomainList.builtIn`.
    var typedDomains: [String] { state?.typedDomains ?? [] }

    /// How many more sites can be added by name before the filter is full.
    var remainingSiteSlots: Int {
        max(0, AdultDomainList.userSlots - typedDomains.count)
    }

    // MARK: - Writing (one direction only)

    enum AddSiteError: LocalizedError, Equatable {
        case invalid
        case full
        case alreadyCovered

        var errorDescription: String? {
            switch self {
            case .invalid: "That doesn't look like a website address. Try something like example.com."
            case .full: "The filter is full: iOS allows \(AdultDomainList.filterCapacity) named sites. Apple's adult filter still covers the rest."
            case .alreadyCovered: "That site is already blocked by name."
            }
        }
    }

    /// Switches the guard on, for good, with whatever the user picked. The
    /// record is written before the restriction so a crash in between leaves
    /// a guard that re-asserts itself on the next launch rather than one that
    /// silently never existed.
    func enable(selection: FamilyActivitySelection) {
        guard let state else { return }
        state.markEnabled()
        state.addApplications(selection.applicationTokens)
        state.addCategories(selection.categoryTokens)
        state.addWebDomains(selection.webDomainTokens)
        apply()
    }

    /// Puts more apps, categories or picker websites behind the guard. The
    /// picker lets things be unticked; that is ignored — the union is what is
    /// kept.
    func add(selection: FamilyActivitySelection) {
        guard let state, state.isEnabled else { return }
        state.addApplications(selection.applicationTokens)
        state.addCategories(selection.categoryTokens)
        state.addWebDomains(selection.webDomainTokens)
        apply()
    }

    /// Blocks one more site by name. Returns the normalised domain that was
    /// added.
    @discardableResult
    func addSite(_ raw: String) throws -> String {
        guard let state, state.isEnabled else { throw AddSiteError.invalid }
        guard let domain = BlockDomain.normalize(raw) else { throw AddSiteError.invalid }
        if AdultDomainList.builtIn.contains(domain) || state.typedDomains.contains(domain) {
            throw AddSiteError.alreadyCovered
        }
        guard remainingSiteSlots > 0 else { throw AddSiteError.full }
        state.addTypedDomains([domain], cap: AdultDomainList.userSlots)
        apply()
        return domain
    }

    /// Rewrites the guard's settings from its record. Called on every launch.
    func reassertIfEnabled() {
        guard isEnabled else { return }
        apply()
    }

    // MARK: - The restriction itself

    private func apply() {
        guard let state else { return }
        store.webContentFilter = AdultDomainList.policy(typedDomains: state.typedDomains)

        let apps = state.applicationTokens
        let categories = state.categoryTokens
        let webDomains = state.webDomainTokens
        store.shieldedApplications = apps.isEmpty ? nil : apps
        // A category has to be shielded on both the app side and the web side,
        // or it locks apps and leaves their websites open (QA-9).
        store.shieldedApplicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shieldedWebDomainCategories = categories.isEmpty ? nil : .specific(categories)
        store.shieldedWebDomains = webDomains.isEmpty ? nil : webDomains
    }
}

/// The slice of `ManagedSettingsStore` the guard writes. The real store
/// conforms below; the tests substitute a recorder.
protocol AdultContentGuardStore: AnyObject {
    var webContentFilter: WebContentSettings.FilterPolicy? { get set }
    var shieldedApplications: Set<ApplicationToken>? { get set }
    var shieldedApplicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>? { get set }
    var shieldedWebDomainCategories: ShieldSettings.ActivityCategoryPolicy<WebDomain>? { get set }
    var shieldedWebDomains: Set<WebDomainToken>? { get set }
}

extension ManagedSettingsStore: AdultContentGuardStore {
    var webContentFilter: WebContentSettings.FilterPolicy? {
        get { webContent.blockedByFilter }
        set { webContent.blockedByFilter = newValue }
    }
    var shieldedApplications: Set<ApplicationToken>? {
        get { shield.applications }
        set { shield.applications = newValue }
    }
    var shieldedApplicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>? {
        get { shield.applicationCategories }
        set { shield.applicationCategories = newValue }
    }
    var shieldedWebDomainCategories: ShieldSettings.ActivityCategoryPolicy<WebDomain>? {
        get { shield.webDomainCategories }
        set { shield.webDomainCategories = newValue }
    }
    var shieldedWebDomains: Set<WebDomainToken>? {
        get { shield.webDomains }
        set { shield.webDomains = newValue }
    }
}
