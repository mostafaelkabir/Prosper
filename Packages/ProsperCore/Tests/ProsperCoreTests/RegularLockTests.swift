import Foundation
import Testing
@testable import ProsperCore

/// QA-12: the Lock tab's Regular lock, saved in settings.json.
struct RegularLockTests {
    @Test("Until edited, the Regular lock is every listed platform for an hour")
    func standardCoversListedPlatforms() {
        let lock = MacSettings().effectiveRegularLock
        #expect(lock.minutes == 60)
        for id in ["facebook", "instagram", "youtube", "tiktok", "x", "reddit", "snapchat", "pinterest"] {
            #expect(lock.platformIDs.contains(id), "missing \(id)")
        }
        for id in ["zoom", "slack", "teams", "gmail"] {
            #expect(!lock.platformIDs.contains(id), "work tool \(id) should not be in it")
        }
    }

    @Test("A settings file from before the Regular lock still loads, with the standard lock")
    func oldSettingsDecode() throws {
        let old = #"{"classOverrides":{},"rememberedDomains":["espn.com"],"dailyDistractingGoalMinutes":45,"onboarded":true}"#
        let settings = try MacStore.decoder.decode(MacSettings.self, from: Data(old.utf8))
        #expect(settings.onboarded)
        #expect(settings.regularLock == nil)
        #expect(settings.effectiveRegularLock == .standard)
    }

    @Test("Starting the standard Regular lock makes an ordinary session over every listed platform")
    func startsSession() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lock = RegularLock.standard
        let (rules, session) = try RulesBook.startingSession(.empty, minutes: lock.minutes, domains: lock.domains, bundleIDs: Array(lock.apps.keys),
                                                             platformIDs: lock.platformIDs, appNames: lock.apps, now: now)
        #expect(Set(session.platformIDs) == Set(lock.platformIDs))
        #expect(session.endsAt == now.addingTimeInterval(3600))
        #expect(rules.sessions.count == 1)
    }

    @Test("An edited Regular lock round-trips through settings.json")
    func editedRoundTrips() throws {
        var settings = MacSettings(onboarded: true)
        settings.regularLock = RegularLock(platformIDs: ["youtube", "reddit"], domains: ["espn.com"], apps: ["com.valvesoftware.steam": "Steam"], minutes: 120)
        let back = try MacStore.decoder.decode(MacSettings.self, from: MacStore.encoder.encode(settings))
        #expect(back == settings)
        #expect(back.effectiveRegularLock.minutes == 120)
    }
}
