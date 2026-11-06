import Foundation
import Testing
import ManagedSettings
import FamilyControls
@testable import Prosper

/// The Adult Content Guard ships two silent pieces: a list of names that must
/// reach Apple's filter in exactly the form it expects, and a record that must
/// only ever grow. A wrong answer in either is invisible until the one night
/// it matters (E9).
struct AdultContentGuardTests {

    /// A throwaway defaults domain per test, so nothing leaks between runs —
    /// and nothing touches the real App Group, where the guard is permanent.
    private func freshState() -> SharedGuardState {
        SharedGuardState(defaults: UserDefaults(suiteName: "AdultContentGuardTests.\(UUID().uuidString)")!)
    }

    // MARK: - The list

    @Test("Every built-in domain is already in the filter's canonical form")
    func builtInIsCanonical() {
        for domain in AdultDomainList.builtIn {
            #expect(BlockDomain.normalize(domain) == domain, "\(domain) would not survive normalisation")
        }
    }

    @Test("The built-in list has no duplicates")
    func builtInIsUnique() {
        #expect(Set(AdultDomainList.builtIn).count == AdultDomainList.builtIn.count)
    }

    @Test("The built-in list fits the filter and leaves the user room")
    func builtInLeavesRoom() {
        #expect(AdultDomainList.builtIn.count <= AdultDomainList.filterCapacity)
        #expect(AdultDomainList.userSlots >= 5)
    }

    @Test("User additions are appended, deduplicated and capped at the filter's limit")
    func additionsAreCapped() {
        let withOne = AdultDomainList.domains(adding: ["pornhub.com", "example.com", "example.com"])
        #expect(withOne == AdultDomainList.builtIn + ["example.com"])

        let many = (0..<60).map { "site\($0).com" }
        let full = AdultDomainList.domains(adding: many)
        #expect(full.count == AdultDomainList.filterCapacity)
        #expect(Array(full.prefix(AdultDomainList.builtIn.count)) == AdultDomainList.builtIn)
    }

    @Test("The guard policy is Apple's adult filter plus every name, with no exceptions")
    func guardPolicy() throws {
        let policy = AdultDomainList.policy(typedDomains: ["example.com"])
        guard case .auto(let blocked, let except) = policy else {
            Issue.record("Expected .auto, got \(policy)")
            return
        }
        #expect(except.isEmpty)
        #expect(blocked.count == AdultDomainList.builtIn.count + 1)
        #expect(blocked.contains(WebDomain(domain: "pornhub.com")))
        #expect(blocked.contains(WebDomain(domain: "example.com")))
    }

    @Test("A block session keeps using .specific until the guard is on, then carries the adult filter")
    func sessionPolicy() {
        let reddit: Set<WebDomain> = [WebDomain(domain: "reddit.com")]
        #expect(AdultDomainList.sessionPolicy(domains: [], guardOn: false) == nil)
        #expect(AdultDomainList.sessionPolicy(domains: [], guardOn: true) == nil)
        #expect(AdultDomainList.sessionPolicy(domains: ["reddit.com"], guardOn: false) == .specific(reddit))
        #expect(AdultDomainList.sessionPolicy(domains: ["reddit.com"], guardOn: true) == .auto(reddit, except: []))
    }

    // MARK: - The record

    @Test("A fresh record is off and covers nothing")
    func freshRecord() {
        let state = freshState()
        #expect(!state.isEnabled)
        #expect(state.enabledAt == nil)
        #expect(state.typedDomains.isEmpty)
        #expect(state.applicationTokens.isEmpty)
        #expect(state.categoryTokens.isEmpty)
        #expect(state.webDomainTokens.isEmpty)
        #expect(!state.covers(application: nil))
        #expect(!state.covers(category: nil))
        #expect(!state.covers(webDomain: nil))
    }

    @Test("Switching on is recorded once; a second switch keeps the first date")
    func enableIsOneWay() {
        let state = freshState()
        let first = Date(timeIntervalSince1970: 1_000)
        state.markEnabled(at: first)
        #expect(state.isEnabled)
        #expect(state.enabledAt == first)

        state.markEnabled(at: first.addingTimeInterval(86_400))
        #expect(state.enabledAt == first)
    }

    @Test("Typed sites append in order, skip repeats and stop at the cap")
    func typedSitesAppendOnly() {
        let state = freshState()
        #expect(state.addTypedDomains(["a.com", "b.com", "a.com"], cap: 3) == ["a.com", "b.com"])
        #expect(state.typedDomains == ["a.com", "b.com"])

        #expect(state.addTypedDomains(["c.com", "d.com"], cap: 3) == ["c.com"])
        #expect(state.typedDomains == ["a.com", "b.com", "c.com"])

        #expect(state.addTypedDomains(["b.com"], cap: 10).isEmpty)
        #expect(state.typedDomains == ["a.com", "b.com", "c.com"])
    }

    // MARK: - The service

    /// Records what the guard hands to iOS, instead of the simulator's store.
    private final class RecordingStore: AdultContentGuardStore {
        var webContentFilter: WebContentSettings.FilterPolicy?
        var shieldedApplications: Set<ApplicationToken>?
        var shieldedApplicationCategories: ShieldSettings.ActivityCategoryPolicy<Application>?
        var shieldedWebDomainCategories: ShieldSettings.ActivityCategoryPolicy<WebDomain>?
        var shieldedWebDomains: Set<WebDomainToken>?
        var writes = 0 { didSet {} }
    }

    private func freshGuard() -> (AdultContentGuard, RecordingStore, SharedGuardState) {
        let store = RecordingStore()
        let state = freshState()
        return (AdultContentGuard(store: store, state: state), store, state)
    }

    @Test("Switching on writes Apple's adult filter plus the list, and nothing is shielded until apps are added")
    func enableWritesThePolicy() {
        let (guardService, store, state) = freshGuard()
        #expect(!guardService.isEnabled)
        #expect(store.webContentFilter == nil)

        guardService.enable(selection: FamilyActivitySelection())

        #expect(guardService.isEnabled)
        #expect(state.isEnabled)
        #expect(store.webContentFilter == AdultDomainList.policy(typedDomains: []))
        #expect(store.shieldedApplications == nil)
        #expect(store.shieldedApplicationCategories == nil)
        #expect(store.shieldedWebDomainCategories == nil)
        #expect(store.shieldedWebDomains == nil)
    }

    @Test("Re-asserting on launch rewrites the same policy, and does nothing while off")
    func reassert() {
        let (guardService, store, _) = freshGuard()
        guardService.reassertIfEnabled()
        #expect(store.webContentFilter == nil)

        guardService.enable(selection: FamilyActivitySelection())
        store.webContentFilter = nil
        guardService.reassertIfEnabled()
        #expect(store.webContentFilter == AdultDomainList.policy(typedDomains: []))
    }

    @Test("A site added by name is normalised, kept, and reaches the filter")
    func addSite() throws {
        let (guardService, store, _) = freshGuard()
        guardService.enable(selection: FamilyActivitySelection())

        let added = try guardService.addSite("https://www.ExampleMirror.XXX/path?q=1")
        #expect(added == "examplemirror.xxx")
        #expect(guardService.typedDomains == ["examplemirror.xxx"])
        #expect(guardService.remainingSiteSlots == AdultDomainList.userSlots - 1)
        #expect(store.webContentFilter == AdultDomainList.policy(typedDomains: ["examplemirror.xxx"]))
    }

    @Test("Adding a site refuses nonsense, repeats, and anything past the filter's capacity")
    func addSiteRefusals() throws {
        let (guardService, _, _) = freshGuard()

        // Off: nothing can be added yet.
        #expect(throws: AdultContentGuard.AddSiteError.invalid) {
            try guardService.addSite("example.com")
        }

        guardService.enable(selection: FamilyActivitySelection())
        #expect(throws: AdultContentGuard.AddSiteError.invalid) {
            try guardService.addSite("not a domain")
        }
        #expect(throws: AdultContentGuard.AddSiteError.alreadyCovered) {
            try guardService.addSite("PornHub.com")
        }
        try guardService.addSite("one.example")
        #expect(throws: AdultContentGuard.AddSiteError.alreadyCovered) {
            try guardService.addSite("https://one.example/")
        }

        for index in 1..<AdultDomainList.userSlots {
            try guardService.addSite("site\(index).example")
        }
        #expect(guardService.remainingSiteSlots == 0)
        #expect(throws: AdultContentGuard.AddSiteError.full) {
            try guardService.addSite("onemore.example")
        }
        #expect(guardService.typedDomains.count == AdultDomainList.userSlots)
    }

    @Test("Adding an empty set of tokens writes nothing")
    func emptyTokenSetsAreNoOps() {
        let state = freshState()
        state.addApplications([])
        state.addCategories([])
        state.addWebDomains([])
        #expect(state.defaults.data(forKey: "adultGuard.applicationTokens") == nil)
        #expect(state.defaults.data(forKey: "adultGuard.categoryTokens") == nil)
        #expect(state.defaults.data(forKey: "adultGuard.webDomainTokens") == nil)
    }
}
