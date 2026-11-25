import Foundation
import FamilyControls
import ManagedSettings
import SwiftData

/// Every label, as one value: the apps and categories under each label and
/// the websites under each label. Distracting is the block list.
///
/// Pure, so tests can check that a thing carries one label at a time.
struct LabelBook: Equatable {
    var productive = FamilyActivitySelection()
    var distracting = FamilyActivitySelection()
    var rest = FamilyActivitySelection()
    var productiveDomains: [String] = []
    var distractingDomains: [String] = []
    var restDomains: [String] = []

    init() {}

    init(settings s: UserSettings) {
        productive = WasteSelectionCodec.decode(s.productiveSelectionData)
        distracting = WasteSelectionCodec.decode(s.wasteAppSelectionData)
        rest = WasteSelectionCodec.decode(s.restSelectionData)
        productiveDomains = s.productiveDomains
        distractingDomains = s.wasteDomains
        restDomains = s.restDomains
    }

    /// The label `target` carries now, through the same rules the report
    /// files time by.
    func current(_ target: LabelTarget) -> TimeClass {
        target.currentClass(in: SharedClassification.Snapshot(
            productive: productive, distracting: distracting, rest: rest,
            productiveDomains: productiveDomains, distractingDomains: distractingDomains,
            restDomains: restDomains
        ))
    }

    /// Whether `target` has a label of the person's own (a platform's
    /// built-in label does not count: it can be replaced, not removed).
    func hasOwnLabel(_ target: LabelTarget) -> Bool {
        switch target {
        case .platform(let id):
            guard let platform = PlatformCatalog.platform(id: id) else { return false }
            return classOf(domain: platform.primaryDomain) != nil
        case .app(let token, _):
            return [productive, distracting, rest].contains { $0.applicationTokens.contains(token) }
        case .site(let domain):
            return classOf(domain: domain) != nil
        }
    }

    /// Gives `target` the label `label`, taking it out of any other; nil
    /// takes its own label away. A platform moves all its domains together.
    mutating func assign(_ label: TimeClass?, to target: LabelTarget) {
        switch target {
        case .platform(let id):
            guard let platform = PlatformCatalog.platform(id: id) else { return }
            for domain in platform.domains { clear(domain) }
            if let label { for domain in platform.domains { file(domain, under: label) } }
        case .app(let token, _):
            productive.applicationTokens.remove(token)
            distracting.applicationTokens.remove(token)
            rest.applicationTokens.remove(token)
            switch label {
            case .productive: productive.applicationTokens.insert(token)
            case .distracting: distracting.applicationTokens.insert(token)
            case .rest: rest.applicationTokens.insert(token)
            case .unclassified, nil: break
            }
        case .site(let domain):
            clear(domain)
            if let label { file(domain, under: label) }
        }
    }

    // MARK: - Domains

    func classOf(domain: String) -> TimeClass? {
        // Distracting > rest > productive, matching the report (QA-1).
        if distractingDomains.contains(domain) { return .distracting }
        if restDomains.contains(domain) { return .rest }
        if productiveDomains.contains(domain) { return .productive }
        return nil
    }

    mutating func clear(_ domain: String) {
        productiveDomains.removeAll { $0 == domain }
        distractingDomains.removeAll { $0 == domain }
        restDomains.removeAll { $0 == domain }
    }

    mutating func file(_ domain: String, under label: TimeClass) {
        switch label {
        case .productive: productiveDomains.append(domain)
        case .distracting: distractingDomains.append(domain)
        case .rest: restDomains.append(domain)
        case .unclassified: break
        }
    }
}

/// Saving labels, from Label your day and from the one-tap label sheet alike.
@MainActor
enum LabelStore {
    /// Writes `book` and everything that follows from it: the snapshot the
    /// report extension files time by, and the warning schedule (Distracting
    /// is the block list). Returns newly distracting sites that some schedule
    /// lacks, for the caller to offer (UX-26).
    @discardableResult
    static func save(_ book: LabelBook, context: ModelContext) -> [String] {
        let s = UserSettings.current(context: context)
        let offer = ScheduledLockService.shared.sitesWorthOffering(old: s.wasteDomains, new: book.distractingDomains)
        s.productiveSelectionData = WasteSelectionCodec.encode(book.productive)
        s.productiveDomains = book.productiveDomains
        s.restSelectionData = WasteSelectionCodec.encode(book.rest)
        s.restDomains = book.restDomains
        s.wasteAppSelectionData = WasteSelectionCodec.encode(book.distracting)
        s.wasteAppCount = book.distracting.applicationTokens.count + book.distracting.categoryTokens.count
        s.wasteDomains = book.distractingDomains
        try? context.save()
        s.syncClassificationSnapshot()
        WarningService.shared.refreshSchedule(
            enabled: s.warningsEnabled,
            selection: book.distracting,
            typedDomains: book.distractingDomains,
            thresholdMinutes: s.wasteWarningThresholdMinutes
        )
        return offer
    }

    /// One label for one thing, saved.
    @discardableResult
    static func apply(_ label: TimeClass?, to target: LabelTarget, context: ModelContext) -> [String] {
        var book = LabelBook(settings: UserSettings.current(context: context))
        book.assign(label, to: target)
        return save(book, context: context)
    }
}
