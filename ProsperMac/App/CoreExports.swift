// The shared core is visible in every file of the Mac app, including the
// Aurora components compiled by path from the iOS app (project.yml), which
// cannot import it themselves without breaking the iOS build.
@_exported import ProsperCore
import Foundation

extension TimeInterval {
    /// "2h 14m", "14m", or "<1m". Same wording as the iPhone's report.
    var usageFormatted: String {
        let totalMinutes = Int(self / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return self > 0 ? "<1m" : "0m"
    }
}

extension TimeClassKind {
    /// The Aurora class this maps to.
    var auroraClass: TimeClass {
        switch self {
        case .productive: .productive
        case .distracting: .distracting
        case .rest: .rest
        }
    }
}

extension Optional where Wrapped == TimeClassKind {
    var auroraClass: TimeClass { self?.auroraClass ?? .unclassified }
}
