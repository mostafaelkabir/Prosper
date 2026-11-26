#if DEBUG
import AppKit
import SwiftUI

/// `StolenEyes --render-snapshots <folder>` writes each tab, light and dark,
/// as a PNG with sample numbers, then exits. For checking layout without a
/// screen (CI, a locked Mac). `--snapshot-scale 2` for Retina images (the
/// README screenshots); `--via-window` draws through an offscreen window
/// like the app does, which keeps charts and gradients exact. Debug builds only.
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
            ("brand", AnyView(BrandPreview())),
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
                let scale = args.firstIndex(of: "--snapshot-scale").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 1
                let file = folder.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                if args.contains("--via-window") {
                    try? renderViaWindow(content, appearance: appearance, scale: scale)?.write(to: file)
                    continue
                }
                appearance.performAsCurrentDrawingAppearance {
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = scale
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: file)
                    }
                }
            }
        }
        exit(0)
    }

    /// Hosts the view in an offscreen window at its full height and draws it.
    private static func renderViaWindow<V: View>(_ view: V, appearance: NSAppearance, scale: Double) -> Data? {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// The sidebar lockup, the menu bar mark (large and at size) and the resting
/// reveal, for checking the identity pieces that no tab shows on its own.
private struct BrandPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SidebarLockup().frame(width: 220).background(ProsperColor.surface)
            HStack(spacing: 24) {
                Image(nsImage: MenuBarMark.image).resizable().frame(width: 99, height: 72)
                Image(nsImage: MenuBarMark.image)
                GlanceReveal(markSize: 112, autoplay: false)
            }
        }
        .padding(24)
        .foregroundStyle(ProsperColor.ink)
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
