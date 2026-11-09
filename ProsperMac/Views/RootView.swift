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
        Button("Open StolenEyes") { open(.today) }
        Button("Lock now…") { open(.lock) }
        Divider()
        Button("Quit StolenEyes window") { NSApp.terminate(nil) }
            .help("Quitting the window never ends a lock: the helper and the network filter keep running.")
    }

    private func open(_ tab: MacTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "selectedTab")
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
