import CloudKit
import Foundation

/// Turns sync models into CloudKit records and back. Pure, so it is tested
/// without iCloud.
public enum SyncRecords {
    public static let zoneID = CKRecordZone.ID(zoneName: "Prosper", ownerName: CKCurrentUserDefaultName)
    static let deviceType = "DeviceSnapshot"
    static let dayType = "DayReport"

    public enum Item: Equatable {
        case device(DeviceSnapshot)
        case day(DayReport)
    }

    public static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    /// The record for one of this device's items, on top of the server's
    /// system fields when we have them.
    public static func record(for item: Item, systemFields: Data?) -> CKRecord? {
        let name: String
        let type: String
        let payload: Data
        let deviceID: String
        let updatedAt: Date
        switch item {
        case .device(let snapshot):
            name = SyncRecordName.device(snapshot.deviceID)
            type = deviceType
            guard let data = try? SyncStore.encoder.encode(snapshot) else { return nil }
            payload = data
            deviceID = snapshot.deviceID
            updatedAt = snapshot.updatedAt
        case .day(let report):
            name = SyncRecordName.day(device: report.deviceID, day: report.day)
            type = dayType
            guard let data = try? SyncStore.encoder.encode(report) else { return nil }
            payload = data
            deviceID = report.deviceID
            updatedAt = report.updatedAt
        }
        let record = systemFields.flatMap(Self.decodeSystemFields).flatMap { $0.recordID.recordName == name ? $0 : nil }
            ?? CKRecord(recordType: type, recordID: recordID(name))
        record["deviceID"] = deviceID as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        record["payload"] = payload as CKRecordValue
        if case .day(let report) = item { record["day"] = report.day as CKRecordValue }
        return record
    }

    public static func item(from record: CKRecord) -> Item? {
        guard let payload = record["payload"] as? Data else { return nil }
        switch record.recordType {
        case deviceType: return (try? SyncStore.decoder.decode(DeviceSnapshot.self, from: payload)).map(Item.device)
        case dayType: return (try? SyncStore.decoder.decode(DayReport.self, from: payload)).map(Item.day)
        default: return nil
        }
    }

    public static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    public static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
