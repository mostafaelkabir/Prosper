import SwiftUI
import ManagedSettings

/// Something a usage row can be labelled as: a catalog platform (its app and
/// all its sites together), one app, or one website.
///
/// Compiled into the app and the ProsperReport extension, so a row in the
/// report can show the label it is filed under. The report cannot hand a tap
/// back to the app: a link inside it does nothing on a device (UX-31, checked
/// on an iPhone, 2026-11-25). Labels are given in the app, in Label your day.
enum LabelTarget: Hashable {
    case platform(String)
    case app(ApplicationToken, name: String)
    case site(String)

    /// The row's target: its platform when it has one (labelling YouTube covers
    /// the app and every YouTube site), else its app, else its website. Nil
    /// for rows that cannot be labelled this way (categories, unnamed apps).
    init?(item: UsageItem) {
        if let id = item.platformID, PlatformCatalog.platform(id: id) != nil {
            self = .platform(id)
        } else if let platform = PlatformCatalog.match(item.name) {
            self = .platform(platform.id)
        } else if let token = item.appToken {
            self = .app(token, name: item.name)
        } else if item.webToken != nil || item.name.contains("."),
                  let domain = BlockDomain.normalize(item.name) {
            self = .site(domain)
        } else {
            return nil
        }
    }

    /// The label this target carries in `snapshot`, the way the report files
    /// it: the person's own label first, then a platform's built-in one.
    func currentClass(in snapshot: SharedClassification.Snapshot) -> TimeClass {
        switch self {
        case .platform(let id):
            guard let platform = PlatformCatalog.platform(id: id) else { return .unclassified }
            return TimeClass(snapshot.platformClass(platform) ?? platform.defaultClass)
        case .app(let token, let name):
            return TimeClass(snapshot.timeClass(appToken: token, categoryToken: nil, appName: name))
        case .site(let domain):
            return TimeClass(snapshot.timeClass(domain: domain))
        }
    }
}

/// The label a usage row is filed under, as a small badge. Read-only: the
/// report cannot pass a tap to the app, so labels are given in Label your day.
/// Unlabelled rows show nothing, so the list stays quiet.
struct LabelBadge: View {
    let current: TimeClass

    var body: some View {
        if current != .unclassified {
            HStack(spacing: 5) {
                Circle().fill(current.color).frame(width: 7, height: 7)
                Text(current.shortTitle)
                    .scaledFont(12, weight: .semibold)
            }
            .foregroundStyle(current.color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(current.color.opacity(0.13), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Labelled \(current.shortTitle)")
        }
    }
}

extension TimeClass {
    /// The label in one word, for pills.
    var shortTitle: String {
        switch self {
        case .productive: "Productive"
        case .distracting: "Distracting"
        case .rest: "Rest"
        case .unclassified: "Label"
        }
    }
}
