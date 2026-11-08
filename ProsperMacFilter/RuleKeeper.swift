import Foundation
import os.log
import ProsperCore

let filterLog = Logger(subsystem: "com.mostafa.prosper.mac.filter", category: "filter")

/// The extension's own copy of the rules, and the one both providers ask.
///
/// It is the last keeper of the two promises: whatever arrives over XPC is
/// merged add-only into what it already holds (`MacRules.merged`), and the
/// result is saved in the extension's own container, which runs as root and
/// outlives the app, the agent and reboots. Sending it an empty or shortened
/// document changes nothing.
final class RuleKeeper: @unchecked Sendable {
    static let shared = RuleKeeper()

    private let lock = NSLock()
    private var rules: MacRules
    private var active: ActiveRules
    private var counters = Counters(day: UsageDay.key(for: Date()))
    private var timer: DispatchSourceTimer?
    var filterStartedAt: Date?
    var dnsStartedAt: Date?

    /// Recent DNS answers, address → host, so flows that carry no name can be
    /// named by the address they go to (PLAN.md §3.3, step 3).
    private var addressNames: [String: (host: String, expires: Date)] = [:]

    private struct Counters {
        var day: String
        var blocked = 0
        var unnamed = 0
        var safeSearch = 0
    }

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("rules.json")
    }

    private init() {
        let now = Date()
        let saved = MacStore.read(MacRules.self, from: Self.storeURL) ?? .empty
        rules = saved.merged(with: .empty, at: now)
        active = ActiveRules(rules: rules, at: now)
        filterLog.info("Rule keeper loaded revision \(self.rules.revision), guard \(self.rules.guardState != nil), sessions \(self.rules.sessions.count)")
        startTimer()
    }

    /// The rules in force now. Rebuilt when a lock starts or ends.
    var current: ActiveRules {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if now >= active.validUntil {
            rules = rules.merged(with: .empty, at: now)
            active = ActiveRules(rules: rules, at: now)
        }
        return active
    }

    /// Merges `incoming` add-only and saves. Returns the status after.
    func apply(_ incoming: MacRules) -> FilterStatus {
        lock.lock()
        let now = Date()
        let merged = rules.merged(with: incoming, at: now)
        if !incoming.isPreserved(by: merged, at: now) {
            filterLog.error("Merged rules lost something the sender had; this should be impossible")
        }
        let changed = merged != rules
        rules = merged
        active = ActiveRules(rules: rules, at: now)
        lock.unlock()
        if changed {
            do {
                try MacStore.write(merged, to: Self.storeURL)
            } catch {
                filterLog.error("Could not save rules: \(error.localizedDescription, privacy: .public)")
            }
            filterLog.info("Applied rules revision \(merged.revision); guard \(merged.guardState != nil), locks \(merged.sessions.count + merged.schedules.count)")
        }
        return status()
    }

    /// The rules document as held now, for agents that lost theirs.
    var document: MacRules {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    func status() -> FilterStatus {
        lock.lock()
        defer { lock.unlock() }
        rollCounters()
        let now = Date()
        return FilterStatus(
            filterStartedAt: filterStartedAt,
            dnsStartedAt: dnsStartedAt,
            rulesRevision: rules.revision,
            guardOn: rules.guardState != nil,
            activeLocks: rules.sessions.filter { $0.isActive(at: now) }.count + rules.schedules.filter { $0.window.contains(now) }.count,
            blockedToday: counters.blocked,
            unnamedToday: counters.unnamed,
            safeSearchRewritesToday: counters.safeSearch,
            day: counters.day
        )
    }

    // MARK: - Counters

    func countBlocked() { bump { $0.blocked += 1 } }
    func countUnnamed() { bump { $0.unnamed += 1 } }
    func countSafeSearch() { bump { $0.safeSearch += 1 } }

    private func bump(_ change: (inout Counters) -> Void) {
        lock.lock()
        rollCounters()
        change(&counters)
        lock.unlock()
    }

    private func rollCounters() {
        let today = UsageDay.key(for: Date())
        if counters.day != today { counters = Counters(day: today) }
    }

    // MARK: - Address map

    func remember(host: String, addresses: [String], ttl: UInt32) {
        guard !addresses.isEmpty else { return }
        let expires = Date().addingTimeInterval(TimeInterval(min(max(ttl, 60), 3600)))
        lock.lock()
        for address in addresses { addressNames[address] = (host, expires) }
        if addressNames.count > 20_000 {
            let now = Date()
            addressNames = addressNames.filter { $0.value.expires > now }
        }
        lock.unlock()
    }

    func host(forAddress address: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = addressNames[address], entry.expires > Date() else { return nil }
        return entry.host
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in _ = self?.current }
        t.resume()
        timer = t
    }
}
