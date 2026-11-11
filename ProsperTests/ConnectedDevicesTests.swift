import DeviceActivity
import Foundation
import Testing
@testable import Prosper

/// Connected devices (M7.3): what this iPhone tells the Mac.
struct ConnectedDevicesTests {
    static func defaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    // MARK: - Waste markers

    @Test("Markers run every 15 minutes to 4 hours, then every half hour to 8")
    func markerLadder() {
        #expect(WasteMarkLog.minutes.first == 15)
        #expect(WasteMarkLog.minutes.contains(240))
        #expect(!WasteMarkLog.minutes.contains(255))
        #expect(WasteMarkLog.minutes.last == 480)
        #expect(WasteMarkLog.minutes.count == 24)
    }

    @Test("A marker's event name maps back to its minutes; warning events don't")
    func markerNames() {
        #expect(WasteMarkLog.minutes(for: WasteMarkLog.eventName(75)) == 75)
        #expect(WasteMarkLog.minutes(for: WarningLevel.nudge.eventName) == nil)
    }

    @Test("A marker keeps the time it was first reached")
    func firstReachWins() {
        let defaults = Self.defaults()
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        WasteMarkLog.record(minutes: 30, at: first, defaults: defaults)
        WasteMarkLog.record(minutes: 30, at: first.addingTimeInterval(600), defaults: defaults)
        WasteMarkLog.record(minutes: 15, at: first.addingTimeInterval(-900), defaults: defaults)
        let marks = WasteMarkLog.marks(day: DayReport.key(for: first), defaults: defaults)
        #expect(marks.map(\.minutes) == [15, 30])
        #expect(marks.last?.reachedAt == first)
    }

    @Test("Only the last three days of markers are kept")
    func markerRetention() {
        let defaults = Self.defaults()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<5 {
            WasteMarkLog.record(minutes: 15, at: start.addingTimeInterval(Double(day) * 86_400), defaults: defaults)
        }
        #expect(WasteMarkLog.marks(day: DayReport.key(for: start), defaults: defaults).isEmpty)
        #expect(!WasteMarkLog.marks(day: DayReport.key(for: start.addingTimeInterval(4 * 86_400)), defaults: defaults).isEmpty)
    }

    // MARK: - What the iPhone publishes

    @Test("The snapshot names the running lock and the guard, and says it is an iPhone")
    func snapshot() {
        let now = Date()
        let sessions = [
            PhoneSyncBuilder.Session(startedAt: now.addingTimeInterval(-600), endsAt: now.addingTimeInterval(3000), domains: ["reddit.com"], appCount: 2),
            PhoneSyncBuilder.Session(startedAt: now.addingTimeInterval(-7200), endsAt: now.addingTimeInterval(-3600), domains: ["old.com"], appCount: 0),
        ]
        let guardSince = now.addingTimeInterval(-86_400)
        let snapshot = PhoneSyncBuilder.snapshot(deviceID: "phone", sessions: sessions, schedules: [], guardSince: guardSince, measuresWaste: true, appVersion: "1.0", now: now)
        #expect(snapshot.platform == .iPhone)
        #expect(snapshot.guardOn)
        #expect(snapshot.guardSince == guardSince)
        #expect(snapshot.lock?.items == ["reddit.com", "2 apps"])
        #expect(snapshot.lock?.endsAt == now.addingTimeInterval(3000))
    }

    @Test("The day report carries markers, that day's warnings and locks, never minutes it can't know")
    func dayReport() {
        let now = Date()
        let key = DayReport.key(for: now)
        let marks = [WasteMark(minutes: 15, reachedAt: now.addingTimeInterval(-1800)), WasteMark(minutes: 30, reachedAt: now)]
        let warnings = [
            PhoneSyncBuilder.Warning(level: 1, text: "30m in your waste list", at: now),
            PhoneSyncBuilder.Warning(level: 2, text: "yesterday", at: now.addingTimeInterval(-2 * 86_400)),
        ]
        let sessions = [PhoneSyncBuilder.Session(startedAt: now, endsAt: now.addingTimeInterval(3600), domains: ["x.com"], appCount: 1)]
        let report = PhoneSyncBuilder.day(key, deviceID: "phone", marks: marks, sessions: sessions, warnings: warnings, now: now)
        #expect(report.measurement == .wasteMarkers)
        #expect(report.wasteAtLeastSeconds == 30 * 60)
        #expect(report.warnings.map(\.text) == ["30m in your waste list"])
        #expect(report.locksStarted.first?.itemCount == 2)
        #expect(report.totalSeconds == 0)
        #expect(report.top.isEmpty)
    }

    @Test("Schedule windows read the way the iPhone shows them")
    func windowText() {
        let every = PhoneSyncBuilder.Schedule(name: "Bed", startMinute: 22 * 60, endMinute: 7 * 60, weekdays: Set(1...7), isOnNow: false)
        #expect(PhoneSyncBuilder.windowText(every).hasSuffix("· Every day"))
        let weekdays = PhoneSyncBuilder.Schedule(name: "Work", startMinute: 9 * 60, endMinute: 17 * 60, weekdays: Set(2...6), isOnNow: true)
        #expect(PhoneSyncBuilder.windowText(weekdays).hasSuffix("· Weekdays"))
    }
}

/// The build that added iCloud crashed on launch and set the real store aside
/// each time; the fixed build must put it back, not start empty.
struct StoreRecoveryTests {
    @Test("A store set aside with no live store is restored, the fullest copy first")
    func restoresArchivedStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let live = dir.appendingPathComponent("Prosper.store")
        try Data(repeating: 1, count: 4096).write(to: dir.appendingPathComponent("Prosper.store.unreadable-2026-11-10T14-22-59Z"))
        try Data(repeating: 2, count: 16).write(to: dir.appendingPathComponent("Prosper.store-wal.unreadable-2026-11-10T14-22-59Z"))
        try Data(repeating: 3, count: 10).write(to: dir.appendingPathComponent("Prosper.store.unreadable-2026-11-10T14-24-07Z"))
        #expect(PersistenceConfig.restoreArchivedStoreIfMissing(at: live))
        #expect(try Data(contentsOf: live).count == 4096)
        #expect(FileManager.default.fileExists(atPath: live.path + "-wal"))
        // With a live store present nothing is touched.
        #expect(!PersistenceConfig.restoreArchivedStoreIfMissing(at: live))
    }

    @Test("No archive, nothing to do")
    func nothingToRestore() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(!PersistenceConfig.restoreArchivedStoreIfMissing(at: dir.appendingPathComponent("Prosper.store")))
    }
}
