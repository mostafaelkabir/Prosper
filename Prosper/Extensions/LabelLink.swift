import SwiftUI
import ManagedSettings
import FamilyControls

/// Something that can be given a label from a row of usage: a catalog
/// platform (its app and all its sites together), one app, or one website.
///
/// Compiled into the app and the ProsperReport extension. The extension can
/// see what was used but cannot save a label (it cannot write to the App
/// Group), so a row links into the app with `url`, and the app reads it back
/// with `init?(url:)` and shows the one-tap label sheet.
enum LabelTarget: Hashable {
    case platform(String)
    case app(ApplicationToken, name: String)
    case site(String)

    static let scheme = "stolenglance"

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

    var url: URL? {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "label"
        switch self {
        case .platform(let id):
            parts.queryItems = [URLQueryItem(name: "platform", value: id)]
        case .app(let token, let name):
            guard let data = try? JSONEncoder().encode(token) else { return nil }
            parts.queryItems = [
                URLQueryItem(name: "app", value: data.base64EncodedString()),
                URLQueryItem(name: "name", value: name),
            ]
        case .site(let domain):
            parts.queryItems = [URLQueryItem(name: "site", value: domain)]
        }
        return parts.url
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "label",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let id = value("platform"), PlatformCatalog.platform(id: id) != nil {
            self = .platform(id)
        } else if let encoded = value("app"),
                  let data = Data(base64Encoded: encoded),
                  let token = try? JSONDecoder().decode(ApplicationToken.self, from: data) {
            self = .app(token, name: value("name") ?? "This app")
        } else if let raw = value("site"), let domain = BlockDomain.normalize(raw) {
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

/// The label on a usage row: what it is filed under now, and the way to change
/// it. A link, because the report extension can only hand the tap to the app
/// by opening it.
struct LabelPill: View {
    let target: LabelTarget
    let current: TimeClass
    /// In the ledger the card above already names the label, so the pill only
    /// needs to say "change this".
    var compact = false

    var body: some View {
        if let url = target.url {
            Link(destination: url) { pill }
                .buttonStyle(.plain)
                .accessibilityLabel(current == .unclassified ? "Label" : "Label: \(current.shortTitle)")
                .accessibilityHint("Opens the label choices")
        }
    }

    private var pill: some View {
        HStack(spacing: 5) {
            if current == .unclassified {
                Image(systemName: "tag")
                    .scaledFont(11, weight: .semibold)
                Text("Label")
                    .scaledFont(12, weight: .semibold)
            } else if compact {
                Image(systemName: "tag.fill")
                    .scaledFont(11, weight: .semibold)
            } else {
                Circle().fill(current.color).frame(width: 7, height: 7)
                Text(current.shortTitle)
                    .scaledFont(12, weight: .semibold)
            }
        }
        .foregroundStyle(current == .unclassified ? ProsperColor.accent : current.color)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, compact && current != .unclassified ? 9 : 10)
        .padding(.vertical, 6)
        .background((current == .unclassified ? ProsperColor.accent : current.color).opacity(0.13), in: Capsule())
        // A full-size tap target around the small pill.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
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
