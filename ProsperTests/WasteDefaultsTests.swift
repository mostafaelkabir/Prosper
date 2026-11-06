import Testing
import Foundation
import SwiftData
@testable import Prosper

/// The starter waste list a fresh install gets (UX-21).
struct WasteDefaultsTests {

    @Test("Starter list covers the big feeds and fits the web filter")
    func coversTheFeeds() {
        let domains = WasteDefaults.domains
        for site in ["facebook.com", "instagram.com", "tiktok.com", "x.com", "reddit.com", "youtube.com"] {
            #expect(domains.contains(site))
        }
        #expect(domains.count <= BlockingService.maxDomains)
        #expect(Set(domains).count == domains.count)
    }

    @Test("Work tools and messaging are never pre-filled")
    func leavesTheRestAlone() {
        let domains = Set(WasteDefaults.domains)
        for site in ["slack.com", "zoom.us", "mail.google.com", "whatsapp.com", "netflix.com"] {
            #expect(!domains.contains(site))
        }
    }

    @Test("Every starter site is already in the form the filter accepts")
    func normalised() {
        for site in WasteDefaults.domains {
            #expect(BlockDomain.normalize(site) == site)
        }
    }

    // MARK: - Seeding (UX-21, UX-22)

    @MainActor
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: UserSettings.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test("A fresh install gets every starter site")
    @MainActor
    func freshInstall() throws {
        let context = try context()
        WasteDefaults.seedIfNeeded(context: context, schedules: nil)
        let settings = UserSettings.current(context: context)
        #expect(settings.wasteDomains == WasteDefaults.domains)
        #expect(settings.wasteSeedVersion == WasteDefaults.latestVersion)
    }

    @Test("An existing list keeps the user's sites and gains only YouTube")
    @MainActor
    func existingListGainsYouTube() throws {
        let context = try context()
        let settings = UserSettings.current(context: context)
        settings.wasteDomains = ["reddit.com", "news.ycombinator.com"]
        WasteDefaults.seedIfNeeded(context: context, schedules: nil)
        #expect(settings.wasteDomains == ["reddit.com", "news.ycombinator.com", "youtube.com", "youtu.be", "m.youtube.com"])
    }

    @Test("An install that already had batch 2 gains m.youtube.com, in New Block too")
    @MainActor
    func batchThreeReachesNewBlock() throws {
        let context = try context()
        let settings = UserSettings.current(context: context)
        settings.wasteDomains = ["reddit.com", "youtube.com", "youtu.be"]
        settings.savedBlockDomains = ["x.com"]
        settings.wasteSeedVersion = 2
        WasteDefaults.seedIfNeeded(context: context, schedules: nil)
        #expect(settings.wasteDomains == ["reddit.com", "youtube.com", "youtu.be", "m.youtube.com"])
        #expect(settings.savedBlockDomains == ["x.com", "youtube.com", "youtu.be", "m.youtube.com"])
    }

    @Test("Adding never duplicates and never passes the filter limit")
    func addingRespectsLimit() {
        let full = (1...BlockingService.maxDomains).map { "site\($0).com" }
        #expect(WasteDefaults.adding(["youtube.com"], to: full) == full)
        #expect(WasteDefaults.adding(["a.com", "a.com"], to: ["a.com"]) == ["a.com"])
    }

    @Test("A starter site the user removed stays removed")
    @MainActor
    func removalSticks() throws {
        let context = try context()
        WasteDefaults.seedIfNeeded(context: context, schedules: nil)
        let settings = UserSettings.current(context: context)
        settings.wasteDomains.removeAll { $0 == "youtube.com" }
        WasteDefaults.seedIfNeeded(context: context, schedules: nil)
        #expect(!settings.wasteDomains.contains("youtube.com"))
    }
}
