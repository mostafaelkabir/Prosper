import Foundation
import DeviceActivity
import SwiftUI

/// Time-of-day usage, bucketed by (day, hour). Built from an hourly-segmented
/// `DeviceActivityFilter`, so it powers both the single-day 24-hour bars and
/// the 7×24 week grid. Like `UsageSummary`, this is compiled into the app too
/// so the simulator can render sample data.
struct HourlyUsage: Sendable {
    struct Cell: Identifiable, Hashable, Sendable {
        var id: String { "\(Int(day.timeIntervalSince1970))-\(hour)" }
        let day: Date          // start of day
        let hour: Int          // 0...23
        var duration: TimeInterval
    }

    /// Only cells with activity; missing (day, hour) pairs are zero.
    var cells: [Cell] = []
    /// Distinct days that had any activity, ascending.
    var days: [Date] = []

    var totalDuration: TimeInterval { cells.reduce(0) { $0 + $1.duration } }
    var isEmpty: Bool { totalDuration == 0 }
    var isSingleDay: Bool { days.count <= 1 }

    /// The most recent day with data (or today), used as the anchor for the
    /// week grid's rows.
    var latestDay: Date { days.last ?? Calendar.current.startOfDay(for: .now) }

    /// Duration summed per hour across every day (0...23).
    var durationByHour: [TimeInterval] {
        var result = Array(repeating: 0.0, count: 24)
        for cell in cells { result[cell.hour] += cell.duration }
        return result
    }

    /// Largest single (day, hour) cell — the week grid normalizes against this.
    var maxCellDuration: TimeInterval { cells.map(\.duration).max() ?? 0 }

    /// The hour (0...23) with the most time across the range, if any.
    var peakHour: Int? {
        let byHour = durationByHour
        guard let maxValue = byHour.max(), maxValue > 0 else { return nil }
        return byHour.firstIndex(of: maxValue)
    }

    func duration(day: Date, hour: Int) -> TimeInterval {
        cells.first { $0.day == day && $0.hour == hour }?.duration ?? 0
    }

    /// Walks the async result tree and buckets each hourly segment.
    static func build(from data: DeviceActivityResults<DeviceActivityData>) async -> HourlyUsage {
        let calendar = Calendar.current
        var buckets: [Date: [Int: TimeInterval]] = [:]

        for await activity in data {
            for await segment in activity.activitySegments {
                let start = segment.dateInterval.start
                let day = calendar.startOfDay(for: start)
                let hour = calendar.component(.hour, from: start)
                buckets[day, default: [:]][hour, default: 0] += segment.totalActivityDuration
            }
        }

        var cells: [Cell] = []
        for (day, hours) in buckets {
            for (hour, duration) in hours where duration > 0 {
                cells.append(Cell(day: day, hour: hour, duration: duration))
            }
        }

        var usage = HourlyUsage()
        usage.cells = cells.sorted { ($0.day, $0.hour) < ($1.day, $1.hour) }
        usage.days = Set(cells.map(\.day)).sorted()
        return usage
    }
}

/// Formats an hour-of-day (0...23) as "12a", "6a", "12p", "6p", "11p".
func hourLabel(_ hour: Int) -> String {
    let h = ((hour % 24) + 24) % 24
    switch h {
    case 0: return "12a"
    case 12: return "12p"
    case 1...11: return "\(h)a"
    default: return "\(h - 12)p"
    }
}

// MARK: - Sample data
//
// Fabricated numbers, compiled ONLY for the simulator, which has no Screen Time
// to read. A shipped user must never see invented figures presented as their own
// usage, so this is a compile-time guarantee rather than a rule to remember: on
// any device build — debug or release — these declarations do not exist, and a
// call site that forgets its #if fails to build instead of shipping (REL-11).
#if targetEnvironment(simulator)

extension HourlyUsage {
    /// - Parameter dayCount: 1 = a single day's 24-hour bars, >1 = week grid.
    static func sample(days dayCount: Int) -> HourlyUsage {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let count = max(1, min(dayCount, 7))

        // A believable waking-hours curve (minutes per hour, index = hour).
        let base: [Double] = [
            2, 0, 0, 0, 0, 1,      // 0–5  overnight
            6, 14, 22, 12, 9, 11,  // 6–11 morning
            18, 10, 8, 9, 13, 21,  // 12–17 afternoon
            28, 34, 40, 33, 24, 10 // 18–23 evening peak
        ]
        // Normalise so a single day totals 134m, matching Today / Insights /
        // TotalTime sample data (QA-4). The raw curve sums to 325m.
        let sampleDayMinutes = 134.0
        let normalise = sampleDayMinutes / base.reduce(0, +)

        var cells: [Cell] = []
        var days: [Date] = []
        for offset in 0..<count {
            let day = calendar.date(byAdding: .day, value: offset - (count - 1), to: today) ?? today
            days.append(day)
            // Vary each day a little so the grid does not look uniform.
            let scale = [1.0, 0.7, 1.2, 0.9, 1.1, 0.6, 1.15][offset % 7]
            for hour in 0..<24 {
                let minutes = base[hour] * scale * normalise
                if minutes >= 0.5 {
                    cells.append(Cell(day: day, hour: hour, duration: minutes * 60))
                }
            }
        }

        var usage = HourlyUsage()
        usage.cells = cells
        usage.days = days
        return usage
    }
}
#endif
