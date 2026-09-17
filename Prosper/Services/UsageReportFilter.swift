import Foundation
import DeviceActivity

/// Builds the filters the app passes to `DeviceActivityReport`.
/// Every filter is limited to iPhones so data from other devices never mixes in.
enum UsageReportFilter {
    static func today() -> DeviceActivityFilter {
        let start = Calendar.current.startOfDay(for: .now)
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    /// The last seven calendar days, including today, as one segment per day.
    static func lastSevenDays() -> DeviceActivityFilter {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    /// Today, segmented hour by hour — drives the 24-hour "When" bars.
    static func todayHourly() -> DeviceActivityFilter {
        let start = Calendar.current.startOfDay(for: .now)
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    /// The last seven days segmented hour by hour — drives the 7×24 week grid.
    static func lastSevenDaysHourly() -> DeviceActivityFilter {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }
}
