import SwiftUI
import SwiftData
import FamilyControls

/// Where a "label this" link from a usage row lands (tap to label).
///
/// A row in the hosted report opens `stolenglance://label?…`. The app root
/// hands the URL here, and whichever screen is on top shows the sheet: the
/// tab view, or Label your day when that sheet is already open (a sheet
/// cannot be presented from under another one).
@MainActor
@Observable
final class QuickLabelRouter {
    static let shared = QuickLabelRouter()

    struct Request: Identifiable {
        let id = UUID()
        let target: LabelTarget
    }

    var request: Request?
    /// Bumped after every label saved here, so open screens reload.
    private(set) var revision = 0
    /// Screens stacked over the tab view that present the sheet themselves.
    var overlayHosts = 0

    func open(_ url: URL) {
        guard let target = LabelTarget(url: url) else { return }
        request = Request(target: target)
    }

    func didSave() { revision += 1 }
}

extension View {
    /// Shows the one-tap label sheet for links opened while this view is the
    /// top of the stack. `isOverlay` is for screens shown over the tab view.
    func quickLabelSheet(isOverlay: Bool = false) -> some View {
        modifier(QuickLabelHost(isOverlay: isOverlay))
    }
}

private struct QuickLabelHost: ViewModifier {
    let isOverlay: Bool
    @State private var router = QuickLabelRouter.shared

    func body(content: Content) -> some View {
        content
            // A pill drawn in this process (the simulator's example report)
            // comes straight here. On a device the report draws in its own
            // process and its links reach the app through onOpenURL instead.
            .environment(\.openURL, OpenURLAction { url in
                guard LabelTarget(url: url) != nil else { return .systemAction }
                router.open(url)
                return .handled
            })
            .sheet(item: Binding(
                get: { isOverlay || router.overlayHosts == 0 ? router.request : nil },
                set: { router.request = $0 }
            )) { request in
                QuickLabelSheet(target: request.target)
            }
            .onAppear { if isOverlay { router.overlayHosts += 1 } }
            .onDisappear { if isOverlay { router.overlayHosts = max(0, router.overlayHosts - 1) } }
    }
}

/// Label one app, site or platform with one tap.
///
/// A short sheet that rises with a quick, lightly damped spring (Linear's
/// picker sheet, 60fps.design/shots/linear-issue-actions-popup-interaction).
/// The chosen label's tint slides from row to row and its tick pops in,
/// the way Superlist's list pill morphs into the chosen one
/// (60fps.design/shots/superlist-task-to-list-switch); then the sheet saves
/// and lowers itself. Under Reduce Motion the choice simply shows, then the
/// sheet closes.
struct QuickLabelSheet: View {
    let target: LabelTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chosen: TimeClass = .unclassified
    @State private var hasOwnLabel = false
    @State private var loaded = false
    @State private var saving = false
    @State private var taps = 0
    @Namespace private var tint

    private static let choices: [TimeClass] = [.distracting, .productive, .rest]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                VStack(spacing: 8) {
                    ForEach(Self.choices, id: \.self) { label in
                        choiceRow(label)
                    }
                }
                if hasOwnLabel {
                    Button {
                        choose(nil)
                    } label: {
                        Text(removeTitle)
                            .scaledFont(15, weight: .semibold)
                            .foregroundStyle(ProsperColor.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ProsperColor.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sensoryFeedback(.selection, trigger: taps)
        .onAppear(perform: load)
    }

    // MARK: - What is being labelled

    private var header: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(19, weight: .semibold)
                    .foregroundStyle(ProsperColor.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch target {
        case .platform(let id):
            if let platform = PlatformCatalog.platform(id: id) {
                BrandMark(platform: platform, size: 52)
            }
        case .app(let token, _):
            Label(token)
                .labelStyle(.iconOnly)
                .scaleEffect(1.9)
        case .site(let domain):
            SiteIcon(domain: domain, size: 52)
        }
    }

    private var title: String {
        switch target {
        case .platform(let id): PlatformCatalog.platform(id: id)?.name ?? "This platform"
        case .app(_, let name): name
        case .site(let domain): domain
        }
    }

    private var subtitle: String {
        switch target {
        case .platform: "The app and all its websites, together."
        case .app: "This app"
        case .site: "This website"
        }
    }

    private var removeTitle: String {
        if case .platform(let id) = target, PlatformCatalog.platform(id: id)?.defaultClass != nil {
            return "Use the usual label"
        }
        return "Remove label"
    }

    // MARK: - The three labels

    private func choiceRow(_ label: TimeClass) -> some View {
        let selected = chosen == label
        return Button {
            choose(label)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(label.color)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.shortTitle)
                        .scaledFont(17, weight: .semibold)
                        .foregroundStyle(ProsperColor.ink)
                    Text(detail(label))
                        .scaledFont(13)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .scaledFont(22, weight: .semibold)
                        .foregroundStyle(label.color)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(ProsperColor.surface)
                    if selected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(label.color.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(label.color.opacity(0.55), lineWidth: 1.5)
                            }
                            .matchedGeometryEffect(id: "chosen", in: tint)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressScale())
        .disabled(saving)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detail(_ label: TimeClass) -> String {
        switch label {
        case .distracting: "Goes on your block list and counts toward warnings."
        case .productive: "Counts as time well spent."
        case .rest: "Downtime you chose, not wasted."
        case .unclassified: ""
        }
    }

    // MARK: - Saving

    private func load() {
        guard !loaded else { return }
        loaded = true
        let book = LabelBook(settings: UserSettings.current(context: modelContext))
        chosen = book.current(target)
        // A platform whose label is its usual one has nothing to go back to.
        if case .platform(let id) = target, let usual = PlatformCatalog.platform(id: id)?.defaultClass,
           TimeClass(usual) == chosen {
            hasOwnLabel = false
        } else {
            hasOwnLabel = book.hasOwnLabel(target)
        }
    }

    private func choose(_ label: TimeClass?) {
        guard !saving else { return }
        saving = true
        taps += 1
        withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.22)) {
            chosen = label ?? .unclassified
        }
        LabelStore.apply(label, to: target, context: modelContext)
        QuickLabelRouter.shared.didSave()
        AccessibilityNotification.Announcement(
            label.map { "\(title) labelled \($0.shortTitle)" } ?? "Label removed from \(title)"
        ).post()
        // Long enough to see the choice land, short enough to feel instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.25 : 0.5)) { dismiss() }
    }
}

/// A row that gives a little under the finger.
private struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
