import AppKit
import SwiftUI

enum MacTab: String, CaseIterable, Identifiable {
    case today = "Today", insights = "Insights", lock = "Lock", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .insights: "chart.bar.xaxis"
        case .lock: "lock"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("selectedTab") private var tabRaw = MacTab.today.rawValue

    private var tab: Binding<MacTab?> {
        Binding(get: { MacTab(rawValue: tabRaw) ?? .today }, set: { tabRaw = ($0 ?? .today).rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(MacTab.allCases, selection: tab) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .top) { SidebarLockup() }
            .safeAreaInset(edge: .bottom) {
                if let end = model.lockEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(DurationText.countdown(end.timeIntervalSince(context.date)), systemImage: "lock.fill")
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(ProsperColor.accent)
                            .padding(12)
                    }
                }
            }
        } detail: {
            switch tab.wrappedValue ?? .today {
            case .today: TodayView(openLock: { tabRaw = MacTab.lock.rawValue }, openSettings: { tabRaw = MacTab.settings.rawValue })
            case .insights: InsightsView()
            case .lock: LockView()
            case .settings: SettingsView(setup: model.setup)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .tint(ProsperColor.accent)
    }
}

/// The Stolen Glance mark and name at the head of the sidebar, still. The
/// reveal plays on the welcome and replays from Settings, never here.
struct SidebarLockup: View {
    var body: some View {
        HStack(spacing: 9) {
            GlanceMark().frame(width: 32, height: 32)
            Text("Stolen Glance")
                .scaledFont(15, weight: .semibold)
                .tracking(-0.3)
                .foregroundStyle(ProsperColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stolen Glance")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The mark as a menu bar template image: one colour, the keyhole and the
/// gaps around the iris cut out, so macOS tints it for light, dark and a
/// highlighted menu. Drawn from `GlanceGeometry`, like the app icon.
@MainActor
enum MenuBarMark {
    static let image: NSImage = {
        // The eye fills only the middle of the mark's square box, so it is
        // drawn larger and cropped to the eye: 22 x 16 pt, menu bar height.
        let size = NSSize(width: 22, height: 16)
        let mark = GlanceMark()
            .frame(width: 30, height: 30)
            .offset(y: -1.5)
            .frame(width: size.width, height: size.height)
            .clipped()
        let renderer = ImageRenderer(content: mark)
        renderer.scale = 3
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "eye", accessibilityDescription: nil) ?? NSImage()
        image.size = size
        image.isTemplate = true
        image.accessibilityDescription = "Stolen Glance"
        return image
    }()
}

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let end = model.lockEndsAt {
            Text("Locked until \(end.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("No lock running")
        }
        Text("Distracting today: \(model.today.distractingSeconds.usageFormatted)")
        Text("On the Mac today: \(model.today.totalSeconds.usageFormatted)")
        if model.guardOn { Text("Adult Content Guard on") }
        if !model.agentRunning { Text("⚠︎ Helper not running") }
        Divider()
        Button("Open Stolen Glance") { open(.today) }
        Button("Lock now…") { open(.lock) }
        Divider()
        Button("Quit Stolen Glance window") { NSApp.terminate(nil) }
            .help("Quitting the window never ends a lock: the helper and the network filter keep running.")
    }

    private func open(_ tab: MacTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
