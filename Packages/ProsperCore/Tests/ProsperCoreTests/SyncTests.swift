import CloudKit
import Foundation
import Testing
@testable import ProsperCore

/// Connected devices (M7): the parts that decide what is sent and what is
/// shown, tested without iCloud.
struct SyncTests {
    static let day = "2026-11-10"

    static func tempStore(_ device: String = "mac-1") -> SyncStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString).json")
        return SyncStore(url: url, deviceID: device)
    }

    static func report(_ device: String = "mac-1", day: String = day, total: Double = 3600) -> DayReport {
        DayReport(deviceID: device, day: day, measurement: .exact, totalSeconds: total,
                  classSeconds: ["distracting": 1200], top: [UsageLine(name: "YouTube", kind: .platform, seconds: 1200, opens: 3, timeClass: "distracting")])
    }

    // MARK: - Records

    @Test("Record names round-trip, including device IDs with dashes")
    func recordNames() {
        let id = "8A58DDED-DB2D-414D-8839-DEA25831BD9C"
        #expect(SyncRecordName.parse(SyncRecordName.device(id)) == .device(id))
        #expect(SyncRecordName.parse(SyncRecordName.day(device: id, day: Self.day)) == .day(device: id, day: Self.day))
        #expect(SyncRecordName.parse("something.else") == nil)
    }

    @Test("A day report survives the trip through a CloudKit record")
    func dayRecordRoundTrip() throws {
        let report = Self.report()
        let record = try #require(SyncRecords.record(for: .day(report), systemFields: nil))
        #expect(record.recordType == "DayReport")
        #expect(record.recordID.zoneID == SyncRecords.zoneID)
        #expect(record["day"] as? String == Self.day)
        guard case .day(let back)? = SyncRecords.item(from: record) else { Issue.record("not a day"); return }
        #expect(back.content == report.content)
    }

    @Test("A save reuses the server's system fields for its own record only")
    func systemFieldsReuse() throws {
        let snapshot = DeviceSnapshot(deviceID: "mac-1", name: "Mac", platform: .mac)
        let first = try #require(SyncRecords.record(for: .device(snapshot), systemFields: nil))
        let fields = SyncRecords.encodeSystemFields(of: first)
        let again = try #require(SyncRecords.record(for: .device(snapshot), systemFields: fields))
        #expect(again.recordID == first.recordID)
        // Fields from a different record are ignored, never grafted on.
        let other = try #require(SyncRecords.record(for: .day(Self.report()), systemFields: fields))
        #expect(other.recordID.recordName == SyncRecordName.day(device: "mac-1", day: Self.day))
    }

    @Test("Records written by a newer build with unknown fields still decode")
    func forwardCompatible() throws {
        let json = #"{"deviceID":"phone","day":"2026-11-10","measurement":"wasteMarkers","somethingNew":[1,2,3],"wasteMarks":[{"minutes":45,"reachedAt":"2026-11-10T20:00:00Z"}]}"#
        let report = try SyncStore.decoder.decode(DayReport.self, from: Data(json.utf8))
        #expect(report.measurement == .wasteMarkers)
        #expect(report.wasteAtLeastSeconds == 45 * 60)
        #expect(report.top.isEmpty)
    }

    // MARK: - What gets sent

    @Test("Publishing the same state again sends nothing")
    func onlyRealChanges() {
        let store = Self.tempStore()
        let now = Date()
        let snapshot = DeviceSnapshot(deviceID: "mac-1", name: "Mac", platform: .mac, updatedAt: now)
        let first = store.setOwn(snapshot: snapshot, days: [Self.report()], now: now)
        #expect(first.save.count == 2)
        var later = snapshot
        later.updatedAt = now.addingTimeInterval(60)
        var sameDay = Self.report()
        sameDay.updatedAt = now.addingTimeInterval(60)
        let second = store.setOwn(snapshot: later, days: [sameDay], now: now.addingTimeInterval(60))
        #expect(second.save.isEmpty)
        // A real change goes out.
        let third = store.setOwn(snapshot: later, days: [Self.report(total: 7200)], now: now.addingTimeInterval(120))
        #expect(third.save == [SyncRecordName.day(device: "mac-1", day: Self.day)])
    }

    @Test("The device record is re-sent every 15 minutes so last seen stays true")
    func heartbeat() {
        let store = Self.tempStore()
        let now = Date()
        let snapshot = DeviceSnapshot(deviceID: "mac-1", name: "Mac", platform: .mac, updatedAt: now)
        _ = store.setOwn(snapshot: snapshot, days: [], now: now)
        var later = snapshot
        later.updatedAt = now.addingTimeInterval(16 * 60)
        let result = store.setOwn(snapshot: later, days: [], now: later.updatedAt)
        #expect(result.save == [SyncRecordName.device("mac-1")])
    }

    @Test("Reports older than the retention window are deleted from iCloud")
    func retention() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        let store = Self.tempStore()
        let snapshot = DeviceSnapshot(deviceID: "mac-1", name: "Mac", platform: .mac, updatedAt: now)
        _ = store.setOwn(snapshot: snapshot, days: [Self.report(day: "2026-09-01")], now: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!, calendar: calendar)
        let result = store.setOwn(snapshot: snapshot, days: [Self.report()], now: now, calendar: calendar)
        #expect(result.delete == [SyncRecordName.day(device: "mac-1", day: "2026-09-01")])
        #expect(store.snapshot.ownDays.keys.sorted() == [Self.day])
    }

    @Test("The store file survives a reload, and a file for another device is not reused")
    func persistence() {
        let store = Self.tempStore()
        _ = store.setOwn(snapshot: DeviceSnapshot(deviceID: "mac-1", name: "Mac", platform: .mac), days: [Self.report()])
        let reloaded = SyncStore(url: store.url, deviceID: "mac-1")
        #expect(reloaded.snapshot.ownDays[Self.day] != nil)
        let stranger = SyncStore(url: store.url, deviceID: "other")
        #expect(stranger.snapshot.ownDays.isEmpty)
    }

    // MARK: - Mac builder

    @Test("The Mac's day report carries exact totals, top rows and what locks stopped")
    func macDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
        var usage = UsageDay(day: Self.day)
        usage.apps["com.apple.dt.Xcode"] = AppUsage(name: "Xcode", seconds: 3600, opens: 2, category: "public.app-category.developer-tools")
        usage.apps["com.google.Chrome"] = AppUsage(name: "Google Chrome", seconds: 1800, opens: 4, isBrowser: true)
        usage.sites["youtube.com"] = SiteUsage(seconds: 1500, visits: 3)
        usage.unlocks = 5
        let rules = MacRules(sessions: [MacLockSession(startedAt: noon, endsAt: noon.addingTimeInterval(3600), platformIDs: ["youtube"])])
        let events = [
            MacEvent(at: noon.addingTimeInterval(60), kind: .siteBlocked, subject: "youtube.com"),
            MacEvent(at: noon.addingTimeInterval(120), kind: .agentStarted, subject: ""),
            MacEvent(at: noon.addingTimeInterval(-86_400), kind: .siteBlocked, subject: "yesterday"),
        ]
        let report = MacSyncBuilder.day(usage, deviceID: "mac-1", settings: MacSettings(), rules: rules, events: events, now: noon, calendar: calendar)
        #expect(report.measurement == .exact)
        #expect(report.totalSeconds == 5400)
        #expect(report.classSeconds["productive"] == 3600)
        #expect(report.distractingSeconds == 1500)
        #expect(report.top.first?.name == "Xcode")
        #expect(report.top.contains { $0.name == "YouTube" && $0.kind == .platform })
        #expect(report.unlocks == 5)
        #expect(report.blockedAttempts == 1)
        #expect(report.locksStarted.count == 1)
    }

    @Test("The Mac's snapshot names what is locked and whether the guard is on")
    func macSnapshot() {
        let now = Date()
        let rules = MacRules(
            sessions: [
                MacLockSession(startedAt: now.addingTimeInterval(-600), endsAt: now.addingTimeInterval(3000), domains: ["reddit.com"], bundleIDs: ["com.apple.calculator"], platformIDs: ["youtube"], appNames: ["com.apple.calculator": "Calculator"]),
                MacLockSession(startedAt: now.addingTimeInterval(-7200), endsAt: now.addingTimeInterval(-3600), domains: ["old.com"]),
            ],
            guardState: MacGuardState(enabledAt: now.addingTimeInterval(-86_400))
        )
        let snapshot = MacSyncBuilder.snapshot(deviceID: "mac-1", name: "Mostafa's Mac", rules: rules, appVersion: "0.1", now: now)
        #expect(snapshot.guardOn)
        #expect(snapshot.lock?.items == ["YouTube", "reddit.com", "Calculator"])
        #expect(snapshot.lock?.endsAt == now.addingTimeInterval(3000))
    }

    @Test("A reinstalled iPhone shows once, as its freshest record")
    func duplicateDevices() {
        var file = SyncFile(deviceID: "mac-1")
        let now = Date()
        file.remote["old"] = RemoteDevice(snapshot: DeviceSnapshot(deviceID: "old", name: "iPhone", platform: .iPhone, updatedAt: now.addingTimeInterval(-86_400)))
        file.remote["new"] = RemoteDevice(snapshot: DeviceSnapshot(deviceID: "new", name: "iPhone", platform: .iPhone, updatedAt: now))
        file.remote["gone"] = RemoteDevice(snapshot: DeviceSnapshot(deviceID: "gone", name: "Old Mac", platform: .mac, updatedAt: now.addingTimeInterval(-40 * 86_400)))
        #expect(file.devices.map(\.id) == ["new"])
    }
}
