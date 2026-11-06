import Foundation
import ManagedSettings

/// The Adult Content Guard's record in the shared App Group (E9).
///
/// Two readers: the app, to know the guard is on and re-assert it on launch,
/// and the Shield extension, to recognise an app it is covering and show the
/// guard's own words rather than a block's countdown. Kept to Foundation and
/// ManagedSettings so the Shield target can compile it.
///
/// There is no `clear`, `remove` or `disable` here, and that is the design.
/// The guard is one-way: the date it was switched on is written once and never
/// overwritten, every set only grows, and "Delete my data" leaves this record
/// alone. The only thing that removes it is removing the app.
struct SharedGuardState {
    let defaults: UserDefaults

    /// Must match `PersistenceConfig.appGroupID`. Duplicated so the Shield
    /// target can compile this file without the rest of the app.
    static let appGroupID = "group.com.mostafa.prosper"

    static var appGroup: SharedGuardState? {
        UserDefaults(suiteName: appGroupID).map { SharedGuardState(defaults: $0) }
    }

    private enum Key {
        static let enabledAt = "adultGuard.enabledAt"
        static let applications = "adultGuard.applicationTokens"
        static let categories = "adultGuard.categoryTokens"
        static let webDomains = "adultGuard.webDomainTokens"
        static let typedDomains = "adultGuard.typedDomains"
    }

    // MARK: - On / off (there is no off)

    /// When the guard was switched on, or nil if it never was.
    var enabledAt: Date? {
        defaults.object(forKey: Key.enabledAt) as? Date
    }

    var isEnabled: Bool { enabledAt != nil }

    /// Records the moment the guard was switched on. Idempotent: a second call
    /// keeps the original date, so nothing can "re-enable" its way to a reset.
    func markEnabled(at date: Date = .now) {
        guard enabledAt == nil else { return }
        defaults.set(date, forKey: Key.enabledAt)
    }

    // MARK: - What it covers

    var applicationTokens: Set<ApplicationToken> { decode(Key.applications) }
    var categoryTokens: Set<ActivityCategoryToken> { decode(Key.categories) }
    var webDomainTokens: Set<WebDomainToken> { decode(Key.webDomains) }

    /// Sites the user added by name, in the order they were added.
    var typedDomains: [String] {
        defaults.stringArray(forKey: Key.typedDomains) ?? []
    }

    /// Append-only. Anything already covered stays covered.
    func addApplications(_ tokens: Set<ApplicationToken>) {
        guard !tokens.isEmpty else { return }
        encode(applicationTokens.union(tokens), Key.applications)
    }

    func addCategories(_ tokens: Set<ActivityCategoryToken>) {
        guard !tokens.isEmpty else { return }
        encode(categoryTokens.union(tokens), Key.categories)
    }

    func addWebDomains(_ tokens: Set<WebDomainToken>) {
        guard !tokens.isEmpty else { return }
        encode(webDomainTokens.union(tokens), Key.webDomains)
    }

    /// Appends sites by name, skipping ones already present and anything past
    /// `cap`. Returns the domains that were actually added.
    @discardableResult
    func addTypedDomains(_ domains: [String], cap: Int) -> [String] {
        var current = typedDomains
        var added: [String] = []
        for domain in domains where !current.contains(domain) && current.count < cap {
            current.append(domain)
            added.append(domain)
        }
        if !added.isEmpty {
            defaults.set(current, forKey: Key.typedDomains)
        }
        return added
    }

    // MARK: - Shield lookups

    func covers(application token: ApplicationToken?) -> Bool {
        guard let token else { return false }
        return applicationTokens.contains(token)
    }

    func covers(category token: ActivityCategoryToken?) -> Bool {
        guard let token else { return false }
        return categoryTokens.contains(token)
    }

    func covers(webDomain token: WebDomainToken?) -> Bool {
        guard let token else { return false }
        return webDomainTokens.contains(token)
    }

    // MARK: - Storage

    private func decode<T: Decodable & Hashable>(_ key: String) -> Set<T> {
        guard let data = defaults.data(forKey: key),
              let set = try? JSONDecoder().decode(Set<T>.self, from: data) else { return [] }
        return set
    }

    private func encode<T: Encodable & Hashable>(_ set: Set<T>, _ key: String) {
        guard let data = try? JSONEncoder().encode(set) else { return }
        defaults.set(data, forKey: key)
    }
}
