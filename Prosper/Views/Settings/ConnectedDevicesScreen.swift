import SwiftUI

/// Settings ▸ Connected devices (M7.5). The connection is the iCloud account
/// already signed in on the iPhone; this screen says whether it works and
/// which devices are on it.
struct ConnectedDevicesScreen: View {
    @ObservedObject private var connected = ConnectedDevices.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProsperCard {
                    ConnectedDevicesPanel(status: connected.status, thisDevice: "This iPhone", devices: connected.devices,
                                          otherPlatform: .mac) {
                        Task { await connected.syncNow() }
                    }
                }
                ForEach(connected.devices) { device in
                    RemoteDeviceCard(device: device)
                }
                ProsperCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What this iPhone shares").labelCaps()
                        Text("Locks and schedules, the Adult Content Guard, warnings, and a marker every 15 minutes of time in your waste list. iOS doesn't let apps send exact per-app minutes anywhere, so your Mac sees \"at least\" figures from this iPhone, while this iPhone sees your Mac's exact ones.")
                            .scaledFont(13)
                            .foregroundStyle(ProsperColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(ProsperColor.background)
        .navigationTitle("Connected devices")
        .navigationBarTitleDisplayMode(.inline)
        .task { await connected.syncNow() }
        .refreshable { await connected.syncNow() }
    }
}
