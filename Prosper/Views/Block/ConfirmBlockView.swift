import SwiftUI
import FamilyControls
import ManagedSettings

/// The last screen before a block starts, and the only one that names what is
/// about to be taken away (REL-9).
///
/// Going straight from the picker to hold-to-lock was how someone could lock
/// away something they needed for a day without ever seeing its name. Picking a
/// *category* is the sharp edge: one tap sweeps in every app iOS files under it,
/// including ones the user never chose and cannot see, and the picker gives no
/// way to enumerate them. That cannot be listed, so it is said out loud instead.
struct ConfirmBlockView: View {
    let selection: FamilyActivitySelection
    /// Websites typed by hand; these live in the web content filter, not the
    /// token set, so they are not part of `selection`.
    let typedDomains: [String]
    let duration: TimeInterval
    let onConfirm: () -> Void

    private var endDate: Date { Date.now.addingTimeInterval(duration) }

    private var apps: [ApplicationToken] { Array(selection.applicationTokens) }
    private var categories: [ActivityCategoryToken] { Array(selection.categoryTokens) }
    private var webTokens: [WebDomainToken] { Array(selection.webDomainTokens) }

    /// "until 4:32 PM", or with the day when the block runs past midnight, so
    /// "until 2:15" can never quietly mean tomorrow afternoon.
    private var endText: String {
        Calendar.current.isDateInToday(endDate)
            ? endDate.formatted(date: .omitted, time: .shortened)
            : endDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var durationText: String {
        let minutes = Int(duration.rounded()) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainder)m"
    }

    var body: some View {
        Form {
            durationSection
            if !apps.isEmpty { appsSection }
            if !categories.isEmpty { categoriesSection }
            if !webTokens.isEmpty || !typedDomains.isEmpty { sitesSection }
            if isEmptySelection { emptySection }
            exitSection
        }
        .navigationTitle("Lock this?")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing in Prosper can end this before \(endText).")
                    .font(ProsperFont.insight)
                    .foregroundStyle(ProsperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HoldToLock(title: "Hold to lock", onComplete: onConfirm)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    /// True when the picker gave us no tokens at all — always the case on the
    /// simulator, where FamilyControls authorization does not exist.
    private var isEmptySelection: Bool {
        apps.isEmpty && categories.isEmpty && webTokens.isEmpty && typedDomains.isEmpty
    }

    private var durationSection: some View {
        Section {
            LabeledContent("Locked until", value: endText)
            LabeledContent("That is", value: durationText)
        } header: {
            Text("When it ends")
        }
    }

    private var appsSection: some View {
        Section {
            ForEach(apps, id: \.self) { token in
                Label(token).labelStyle(.titleAndIcon)
            }
        } header: {
            Text("^[\(apps.count) app](inflect: true)")
        }
    }

    private var categoriesSection: some View {
        Section {
            ForEach(categories, id: \.self) { token in
                Label(token).labelStyle(.titleAndIcon)
            }
        } header: {
            Text("^[\(categories.count) category](inflect: true)")
        } footer: {
            Text("A category covers every app iOS files under it — including apps you did not pick yourself, and ones you install later. iOS does not let Prosper list them, so check this is what you want.")
        }
    }

    private var sitesSection: some View {
        Section {
            ForEach(webTokens, id: \.self) { token in
                Label(token).labelStyle(.titleAndIcon)
            }
            ForEach(typedDomains, id: \.self) { domain in
                Label(domain, systemImage: "globe")
            }
        } header: {
            Text("^[\(webTokens.count + typedDomains.count) website](inflect: true)")
        } footer: {
            Text("Blocked in Safari and other browsers on this iPhone only.")
        }
    }

    private var emptySection: some View {
        Section {
            Label("Nothing is selected on this device.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } footer: {
            Text("App and website tokens only exist on a real iPhone with Screen Time access, so there is nothing to list here in the simulator.")
        }
    }

    private var exitSection: some View {
        Section {
            Text(LockExitCopy.short)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
