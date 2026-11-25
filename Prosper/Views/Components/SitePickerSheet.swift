import SwiftUI

/// Picks websites the way an app picker picks apps: a grid of the usual
/// suspects, each with its brand tile, one tap to add or take out, and a
/// field at the top for anything that is not in the grid (UX-28).
///
/// Every list of sites in the app is edited here: the block list, a new
/// block, a running lock (add-only), a schedule.
struct SitePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var domains: [String]
    /// Sites that are locked right now. They show as chosen and cannot be
    /// taken out; this sheet never loosens a lock.
    var lockedDomains: [String] = []
    var limit: Int = BlockingService.maxDomains
    var title = "Websites"
    /// Called after every change, so the owner can save as the user goes.
    var onChange: () -> Void = {}

    @State private var query = ""
    @State private var error: String?
    @FocusState private var fieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10, alignment: .top)]

    /// What is typed, as a site, if it is one.
    private var typedDomain: String? { BlockDomain.normalize(query) }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    /// The grid, narrowed to what is typed.
    private var platforms: [Platform] {
        guard !trimmedQuery.isEmpty else { return PlatformCatalog.all }
        return PlatformCatalog.all.filter { platform in
            platform.name.lowercased().contains(trimmedQuery)
                || platform.domains.contains { $0.contains(trimmedQuery) }
        }
    }

    /// Sites on the list that no tile in the grid stands for.
    private var otherSites: [String] {
        (lockedDomains + domains).filter { !PlatformCatalog.allDomains.contains($0.lowercased()) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    private var totalCount: Int { Set(lockedDomains + domains).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchField
                    if let error {
                        Text(error)
                            .scaledFont(13)
                            .foregroundStyle(ProsperColor.distracting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let typedDomain, isNew(typedDomain) {
                        addTypedRow(typedDomain)
                    }
                    // Typed sites sit above the grid, so one just added is
                    // seen without scrolling past sixteen tiles.
                    if !otherSites.isEmpty, trimmedQuery.isEmpty {
                        otherSection
                    }
                    if !platforms.isEmpty {
                        popularSection
                    } else if typedDomain == nil {
                        Text("No match. Type the full address, like news.com.")
                            .scaledFont(13)
                            .foregroundStyle(ProsperColor.ink2)
                    }
                    Text("^[\(totalCount) site](inflect: true) chosen, of \(limit) at most. Blocked in Safari and other browsers on this iPhone.")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(ProsperColor.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .scaledFont(15, weight: .medium)
                .foregroundStyle(ProsperColor.ink2)
            TextField("Search, or type a site like news.com", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit(submitTyped)
                .onChange(of: query) { _, _ in error = nil }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ProsperColor.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .scaledFont(16)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ProsperColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ProsperColor.line, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func addTypedRow(_ domain: String) -> some View {
        Button {
            add(typed: domain)
        } label: {
            HStack(spacing: 12) {
                SiteIcon(domain: domain, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \(domain)")
                        .scaledFont(15, weight: .semibold)
                        .foregroundStyle(ProsperColor.ink)
                        .lineLimit(1)
                    Text("And every page under it")
                        .scaledFont(12)
                        .foregroundStyle(ProsperColor.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .scaledFont(22)
                    .foregroundStyle(ProsperColor.accent)
            }
            .padding(12)
            .background(ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The grid

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(trimmedQuery.isEmpty ? "Popular · tap to add" : "Matches").labelCaps()
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(platforms) { platform in
                    tile(platform)
                }
            }
        }
    }

    private func tile(_ platform: Platform) -> some View {
        let locked = isLocked(platform)
        let chosen = locked || isChosen(platform)
        return Button {
            toggle(platform)
        } label: {
            VStack(spacing: 7) {
                BrandMark(platform: platform, size: 54)
                    .opacity(chosen ? 1 : 0.92)
                    .overlay(alignment: .topTrailing) {
                        if chosen {
                            Image(systemName: locked ? "lock.circle.fill" : "checkmark.circle.fill")
                                .scaledFont(20)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(ProsperColor.onAccent, ProsperColor.accent)
                                .background(Circle().fill(ProsperColor.background).padding(1))
                                .offset(x: 7, y: -7)
                        }
                    }
                Text(platform.name)
                    .scaledFont(12, weight: chosen ? .semibold : .regular)
                    .foregroundStyle(chosen ? ProsperColor.ink : ProsperColor.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(chosen ? ProsperColor.accent.opacity(0.12) : ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(chosen ? ProsperColor.accent : ProsperColor.line, lineWidth: chosen ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(platform.name)
        .accessibilityValue(locked ? "Locked now" : (chosen ? "Added" : "Not added"))
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    // MARK: - Everything else on the list

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your other sites").labelCaps()
            VStack(spacing: 0) {
                ForEach(otherSites, id: \.self) { domain in
                    let locked = lockedDomains.contains(domain)
                    HStack(spacing: 12) {
                        SiteIcon(domain: domain, size: 32)
                        Text(domain)
                            .scaledFont(15)
                            .foregroundStyle(ProsperColor.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if locked {
                            Image(systemName: "lock.fill")
                                .scaledFont(13)
                                .foregroundStyle(ProsperColor.ink2)
                                .accessibilityLabel("Locked now")
                        } else {
                            Button {
                                remove(domain)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .scaledFont(20)
                                    .foregroundStyle(ProsperColor.ink2)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(domain)")
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, locked ? 16 : 2)
                    .frame(minHeight: 52)
                    if domain != otherSites.last {
                        Divider().overlay(ProsperColor.line).padding(.leading, 56)
                    }
                }
            }
            .background(ProsperColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Changes

    private func isLocked(_ platform: Platform) -> Bool {
        lockedDomains.contains(platform.primaryDomain)
    }

    private func isChosen(_ platform: Platform) -> Bool {
        domains.contains(platform.primaryDomain)
    }

    private func isNew(_ domain: String) -> Bool {
        !domains.contains(domain) && !lockedDomains.contains(domain)
    }

    /// A platform goes in or out whole: every address it answers to.
    private func toggle(_ platform: Platform) {
        error = nil
        if isChosen(platform) {
            domains.removeAll { platform.domains.contains($0) }
        } else {
            let missing = platform.domains.filter(isNew)
            guard totalCount + missing.count <= limit else {
                error = limitMessage
                return
            }
            domains.append(contentsOf: missing)
        }
        onChange()
    }

    private func submitTyped() {
        guard !trimmedQuery.isEmpty else { return }
        guard let domain = typedDomain else {
            // A name that matches exactly one tile is as good as tapping it.
            if platforms.count == 1, let only = platforms.first, !isChosen(only), !isLocked(only) {
                toggle(only)
                query = ""
            } else {
                error = "Type the full address, like news.com."
            }
            return
        }
        add(typed: domain)
    }

    private func add(typed domain: String) {
        error = nil
        guard isNew(domain) else {
            query = ""
            return
        }
        // Typing youtube.com means YouTube, with every address it uses.
        if let platform = PlatformCatalog.all.first(where: { $0.domains.contains(domain) }) {
            if !isChosen(platform) { toggle(platform) }
            if error == nil { query = "" }
            return
        }
        guard totalCount < limit else {
            error = limitMessage
            return
        }
        domains.append(domain)
        query = ""
        fieldFocused = true
        onChange()
    }

    private func remove(_ domain: String) {
        error = nil
        domains.removeAll { $0 == domain }
        onChange()
    }

    private var limitMessage: String {
        "iOS blocks up to \(limit) sites at once. Take one out to add another."
    }
}
