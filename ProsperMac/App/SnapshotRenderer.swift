#if DEBUG
import AppKit
import SwiftUI

/// `StolenEyes --render-snapshots <folder>` writes each tab, light and dark,
/// as a PNG with sample numbers, then exits. For checking layout without a
/// screen (CI, a locked Mac). Debug builds only.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(snapshot: true)
        let views: [(String, AnyView)] = [
            ("today", AnyView(TodayView(openLock: {}, openSettings: {}))),
            ("insights", AnyView(InsightsView())),
            ("lock", AnyView(LockView())),
            ("settings", AnyView(SettingsView(setup: model.setup))),
            ("shield", AnyView(ShieldPreview())),
        ]
        for (name, view) in views {
            for scheme in [ColorScheme.light, .dark] {
                let content = view
                    .environmentObject(model)
                    .environment(\.snapshotMode, true)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 900)
                    .background(ProsperColor.background)
                let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
                appearance.performAsCurrentDrawingAppearance {
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                    }
                }
            }
        }
        exit(0)
    }
}

/// The agent's shield, drawn in the app for the snapshot only.
private struct ShieldPreview: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 54, weight: .semibold)).foregroundStyle(ProsperColor.accent)
            Text("YouTube is locked").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(ProsperColor.ink)
            Text("1:12:09 left").font(ProsperFont.hero(44).monospacedDigit()).foregroundStyle(ProsperColor.ink)
            Text(LockExitCopy.shield.replacingOccurrences(of: "block", with: "lock")).font(.footnote).foregroundStyle(ProsperColor.unclassified)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 500)
        .background(ProsperColor.background)
    }
}
#endif
