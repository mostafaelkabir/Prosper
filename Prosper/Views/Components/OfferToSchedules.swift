import SwiftUI

/// After the waste list gains sites, asks whether existing schedules should
/// get them too (UX-26). Schedules keep their own lists, so without this a
/// site added later never reached them: YouTube missed Work focus.
private struct OfferToSchedules: ViewModifier {
    @Binding var sites: [String]

    private var isPresented: Binding<Bool> {
        Binding(get: { !sites.isEmpty }, set: { if !$0 { sites = [] } })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Add to your schedules too?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Add to all schedules") {
                ScheduledLockService.shared.addToAll(domains: sites)
                sites = []
            }
            Button("Not now", role: .cancel) { sites = [] }
        } message: {
            let missing = ScheduledLockService.shared.locks(missingAnyOf: sites).map(\.name)
            Text("\(sites.joined(separator: ", ")) is not in \(missing.formatted(.list(type: .and))). Schedules that are locking right now get it straight away.")
        }
    }
}

extension View {
    /// Offers newly added waste sites to every schedule that lacks them.
    func offeringNewSitesToSchedules(_ sites: Binding<[String]>) -> some View {
        modifier(OfferToSchedules(sites: sites))
    }
}
