import Foundation
import DeviceActivity

/// Builds the filters the app passes to `DeviceActivityReport`.
/// Every filter is limited to iPhones so data from other devices never mixes in.
enum UsageReportFilter {
    /// Days before today's start that the 7- and 30-day ranges begin, so each
    /// range covers exactly that many calendar days including today.
    static let sevenDaysBack = 6
    static let thirtyDaysBack = 29

    /// Local start of the day `daysBack` days before `now`'s day. Pure, so the
    /// range arithmetic is testable without Screen Time (QA-9): it must land on
    /// a local midnight and never in the future, or a range silently drops a
    /// day or reports nothing.
    static func startDate(daysBack: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -max(0, daysBack), to: todayStart) ?? todayStart
    }

    static func today() -> DeviceActivityFilter {
        daily(from: startDate(daysBack: 0))
    }

    /// The last seven calendar days, including today, as one segment per day.
    static func lastSevenDays() -> DeviceActivityFilter {
        daily(from: startDate(daysBack: sevenDaysBack))
    }

    /// The last 30 days, one segment per day (Insights "30 days" range).
    static func lastThirtyDays() -> DeviceActivityFilter {
        daily(from: startDate(daysBack: thirtyDaysBack))
    }

    /// The last 30 days segmented hour by hour (30-day "When" grid).
    static func lastThirtyDaysHourly() -> DeviceActivityFilter {
        hourly(from: startDate(daysBack: thirtyDaysBack))
    }

    /// Today, segmented hour by hour — drives the 24-hour "When" bars.
    static func todayHourly() -> DeviceActivityFilter {
        hourly(from: startDate(daysBack: 0))
    }

    /// The last seven days segmented hour by hour — drives the 7×24 week grid.
    static func lastSevenDaysHourly() -> DeviceActivityFilter {
        hourly(from: startDate(daysBack: sevenDaysBack))
    }

    private static func daily(from start: Date) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }

    private static func hourly(from start: Date) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: .now)),
            users: .all,
            devices: .init([.iPhone])
        )
    }
}
