import SwiftUI
import FamilyControls

/// The two rows that choose what a lock covers, the same everywhere a list is
/// built: the block list on the Lock tab, a new block, a running lock, a
/// schedule, setup (UX-28). One tap on a row opens the picker; what is chosen
/// shows underneath with its icon.
///
/// Apps can only be chosen in Apple's own picker, which is where iOS hands out
/// the tokens a shield needs. Websites open `SitePickerSheet`.
struct AppsPickRow: View {
    @Binding var selection: FamilyActivitySelection
    var title = "Apps"
    var chipCap = 12
    var onChange: () -> Void = {}

    @State private var isPickerPresented = false

    private var count: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    private var summary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        var parts: [String] = []
        if apps > 0 { parts.append(apps == 1 ? "1 app" : "\(apps) apps") }
        if categories > 0 { parts.append(categories == 1 ? "1 category" : "\(categories) categories") }
        if sites > 0 { parts.append(sites == 1 ? "1 site" : "\(sites) sites") }
        return parts.isEmpty ? "Choose from the apps on this iPhone" : parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            Button {
                isPickerPresented = true
            } label: {
                PickRowLabel(
                    symbol: "square.grid.2x2.fill",
                    title: title,
                    summary: summary,
                    action: count == 0 ? "Add" : "Edit",
                    isEmpty: count == 0
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Apple's app list")
            // On the row that is always there, not on the Group: a modifier
            // on a Group lands on every child, which would present twice.
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $selection)
            .onChange(of: selection) { _, _ in onChange() }
            if count > 0 {
                // A tap gesture, not a Button: inside a Form a button row
                // restyles the labels in it and the chips lost their names.
                SelectionChips(selection: selection, placeholderCount: count, cap: chipCap, large: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { isPickerPresented = true }
                    .accessibilityHidden(true) // the row above already opens the same picker
            }
        }
    }
}

struct SitesPickRow: View {
    @Binding var domains: [String]
    var title = "Websites"
    /// Sites that are locked right now: shown in the picker, not removable.
    var lockedDomains: [String] = []
    var chipCap = 12
    var onChange: () -> Void = {}

    @State private var showPicker = false

    private var summary: String {
        switch domains.count {
        case 0: "Pick from popular sites, or type any address"
        case 1: "1 site"
        default: "\(domains.count) sites"
        }
    }

    var body: some View {
        Group {
            Button {
                showPicker = true
            } label: {
                PickRowLabel(
                    symbol: "globe",
                    title: title,
                    summary: summary,
                    action: domains.isEmpty ? "Add" : "Edit",
                    isEmpty: domains.isEmpty
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPicker) {
                SitePickerSheet(domains: $domains, lockedDomains: lockedDomains, title: title, onChange: onChange)
            }
            if !domains.isEmpty {
                SelectionChips(
                    selection: FamilyActivitySelection(),
                    typedDomains: SiteList.onePerPlatform(domains),
                    cap: chipCap,
                    large: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { showPicker = true }
                .accessibilityHidden(true)
            }
        }
    }

}

/// Plain helpers for a list of sites, kept off the views so they can be used
/// (and tested) from anywhere, not only the main actor.
enum SiteList {
    /// The chips name each platform once. YouTube is three addresses on the
    /// list (youtube.com, youtu.be, m.youtube.com) and one thing to a person.
    static func onePerPlatform(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        return domains.filter { domain in
            guard let platform = PlatformCatalog.all.first(where: { $0.domains.contains(domain) }) else { return true }
            return seen.insert(platform.id).inserted
        }
    }
}

/// Icon tile, title, what is chosen, and a pill that says what a tap does.
struct PickRowLabel: View {
    let symbol: String
    let title: String
    let summary: String
    let action: String
    var isEmpty = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ProsperColor.accent.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ProsperColor.accent)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(ProsperColor.ink)
                Text(summary)
                    .scaledFont(13)
                    .foregroundStyle(ProsperColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Label(action, systemImage: isEmpty ? "plus" : "pencil")
                .labelStyle(.titleAndIcon)
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(isEmpty ? ProsperColor.onAccent : ProsperColor.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isEmpty ? ProsperColor.accent : ProsperColor.accent.opacity(0.14))
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
    }
}
