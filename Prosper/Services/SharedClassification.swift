import Foundation
import FamilyControls
import ManagedSettings

/// The user's four-class classification (UX-9), mirrored into the shared App
/// Group so the ProsperReport extension can turn raw Screen Time into a real
/// `TimeBalance`. The app writes it whenever labels change; the report
/// extension reads it in `makeConfiguration`. Same pattern as `SharedBlockState`
/// — the extension cannot open SwiftData, so we keep a lightweight snapshot in
/// `UserDefaults(suiteName:)`.
///
/// "Distracting" is the existing waste selection, so nothing is duplicated.
/// Anything not listed stays Unclassified — nothing becomes productive by
/// subtraction (UX-9 rule).
enum SharedClassification {
    /// Must match `PersistenceConfig.appGroupID`.
    static let appGroupID = "group.com.mostafa.prosper"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    private static let productiveSelKey = "class.productive.selection"
    private static let distractingSelKey = "class.distracting.selection"
    private static let restSelKey = "class.rest.selection"
    private static let productiveDomainsKey = "class.productive.domains"
    private static let distractingDomainsKey = "class.distracting.domains"
    private static let restDomainsKey = "class.rest.domains"

    // MARK: - Write (app process)

    static func save(
        productive: FamilyActivitySelection,
        distracting: FamilyActivitySelection,
        rest: FamilyActivitySelection,
        productiveDomains: [String],
        distractingDomains: [String],
        restDomains: [String]
    ) {
        guard let defaults else { return }
        defaults.set(encode(productive), forKey: productiveSelKey)
        defaults.set(encode(distracting), forKey: distractingSelKey)
        defaults.set(encode(rest), forKey: restSelKey)
        defaults.set(productiveDomains, forKey: productiveDomainsKey)
        defaults.set(distractingDomains, forKey: distractingDomainsKey)
        defaults.set(restDomains, forKey: restDomainsKey)
    }

    // MARK: - Read (report extension)

    struct Snapshot {
        var productive = FamilyActivitySelection()
        var distracting = FamilyActivitySelection()
        var rest = FamilyActivitySelection()
        var productiveDomains: [String] = []
        var distractingDomains: [String] = []
        var restDomains: [String] = []

        /// True when the user has classified nothing at all — the report shows an
        /// honest "everything is unclassified, go label your apps" state.
        var isEmpty: Bool {
            productive.applicationTokens.isEmpty && productive.categoryTokens.isEmpty &&
            distracting.applicationTokens.isEmpty && distracting.categoryTokens.isEmpty &&
            rest.applicationTokens.isEmpty && rest.categoryTokens.isEmpty &&
            productiveDomains.isEmpty && distractingDomains.isEmpty && restDomains.isEmpty
        }

        /// The class an application token belongs to, or nil if unlabelled. Checks
        /// the app token first, then its category token (a whole-category label).
        func timeClass(appToken: ApplicationToken?, categoryToken: ActivityCategoryToken?) -> ClassKind? {
            if let appToken {
                if productive.applicationTokens.contains(appToken) { return .productive }
                if distracting.applicationTokens.contains(appToken) { return .distracting }
                if rest.applicationTokens.contains(appToken) { return .rest }
            }
            if let categoryToken {
                if productive.categoryTokens.contains(categoryToken) { return .productive }
                if distracting.categoryTokens.contains(categoryToken) { return .distracting }
                if rest.categoryTokens.contains(categoryToken) { return .rest }
            }
            return nil
        }

        /// The class a web domain belongs to, matched by normalised host. A bare
        /// host matches with or without a leading "www.".
        func timeClass(domain: String?) -> ClassKind? {
            guard let host = domain?.lowercased() else { return nil }
            if Self.matches(host, productiveDomains) { return .productive }
            if Self.matches(host, distractingDomains) { return .distracting }
            if Self.matches(host, restDomains) { return .rest }
            return nil
        }

        /// A recorded host matches a tagged entry when it is that domain or any
        /// subdomain of it. Tagging `youtube.com` therefore also catches
        /// `m.youtube.com`, `www.youtube.com` and `music.youtube.com` — the forms
        /// Screen Time actually records for YouTube-in-Safari.
        private static func matches(_ host: String, _ list: [String]) -> Bool {
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return list.contains { entry in
                let e = entry.lowercased()
                let eBare = e.hasPrefix("www.") ? String(e.dropFirst(4)) : e
                return bare == eBare || bare.hasSuffix("." + eBare)
            }
        }
    }

    /// The three classes we can assign; Unclassified is the absence of a match.
    enum ClassKind { case productive, distracting, rest }

    static func load() -> Snapshot {
        guard let defaults else { return Snapshot() }
        return Snapshot(
            productive: decode(defaults.data(forKey: productiveSelKey)),
            distracting: decode(defaults.data(forKey: distractingSelKey)),
            rest: decode(defaults.data(forKey: restSelKey)),
            productiveDomains: defaults.stringArray(forKey: productiveDomainsKey) ?? [],
            distractingDomains: defaults.stringArray(forKey: distractingDomainsKey) ?? [],
            restDomains: defaults.stringArray(forKey: restDomainsKey) ?? []
        )
    }

    // MARK: - Codable helpers

    private static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    private static func decode(_ data: Data?) -> FamilyActivitySelection {
        guard let data else { return FamilyActivitySelection() }
        return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)) ?? FamilyActivitySelection()
    }
}
