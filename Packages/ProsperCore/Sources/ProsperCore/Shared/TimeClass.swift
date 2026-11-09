import Foundation

/// The three classes a person can give an app or site (UX-9). Unclassified is
/// the absence of a match, never a fourth case. iOS calls it
/// `SharedClassification.ClassKind`; the Mac uses it directly.
public enum TimeClassKind: String, Codable, Sendable, Hashable, CaseIterable {
    case productive, distracting, rest
}
