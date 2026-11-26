import AppKit
import SwiftUI

#if DEBUG

/// `StolenEyes --hold-test` presses the real hold-to-confirm button with
/// in-process mouse events (no Accessibility permission needed), on its own
/// and on the Lock screen, prints PASS/FAIL per check and exits 0 or 1.
/// The Lock screen runs on the sample-data model, which never writes rules or
/// calls the filter. Debug builds only.
@MainActor
enum HoldTestHarness {
    private static var failures = 0

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--hold-test") else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        // The full-window checks need the Lock tab; put back the one in use after.
        let savedTab = UserDefaults.standard.string(forKey: "selectedTab")
        UserDefaults.standard.set(MacTab.lock.rawValue, forKey: "selectedTab")
        defer { UserDefaults.standard.set(savedTab, forKey: "selectedTab") }

        // 0. Control: a plain SwiftUI button, to prove the clicks land at all.
        var plainTaps = 0
        let w0 = window(Button("Tap") { plainTaps += 1 }.frame(width: 300, height: 80), size: NSSize(width: 300, height: 80))
        click(at: center(w0), in: w0)
        check("harness: a plain Button receives the click", plainTaps == 1)

        // 1. The hold button on its own.
        var fired = 0
        let w1 = window(HoldToConfirmButton(title: "Hold", action: { fired += 1 }).padding(20), size: NSSize(width: 400, height: 90))
        hold(at: center(w1), in: w1, seconds: 2.2)
        check("button: a 2.2 s hold fires once", fired == 1)
        fired = 0
        hold(at: center(w1), in: w1, seconds: 0.4)
        check("button: a 0.4 s hold does not fire", fired == 0)
        fired = 0
        hold(at: center(w1), in: w1, seconds: 2.2, wiggle: true)
        check("button: a 2.2 s hold with small mouse movement fires once", fired == 1)
        w0.close(); w1.close()

        // 2. The real Lock screen: pick YouTube, hold the lock button.
        lockScenario("Lock screen alone, platform picked") { model in
            AnyView(LockView().environmentObject(model).frame(width: 900, height: 1500).background(ProsperColor.background))
        }
        lockScenario("full window (RootView), platform picked") { model in AnyView(RootView().environmentObject(model)) }
        lockScenario("full window, platform picked, model updating during the hold", churn: true) { model in AnyView(RootView().environmentObject(model)) }
        lockScenario("full window, site typed (text field focused)", typeSite: true) { model in AnyView(RootView().environmentObject(model)) }
        lockScenario("full window, site typed, model updating", typeSite: true, churn: true) { model in AnyView(RootView().environmentObject(model)) }
        lockScenario("Regular lock, nothing chosen", regular: true) { model in AnyView(RootView().environmentObject(model)) }
        lockScenario("Regular lock, model updating", churn: true, regular: true) { model in AnyView(RootView().environmentObject(model)) }
        lockScenario("Regular lock, 0.4 s press", regular: true, holdFor: 0.4) { model in AnyView(RootView().environmentObject(model)) }

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        fflush(stdout)
        UserDefaults.standard.set(savedTab, forKey: "selectedTab")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    /// Opens a Lock screen, chooses something, holds the lock button for
    /// 2.2 s and checks the model was asked to start a lock.
    private static func lockScenario(_ name: String, typeSite: Bool = false, churn: Bool = false, regular: Bool = false, holdFor: Double = 2.2, _ make: (AppModel) -> AnyView) {
        HarnessFrames.frames = [:]
        let model = AppModel(snapshot: true)
        let w = window(make(model), size: NSSize(width: 1000, height: 1500))
        pump(1)
        if regular {
            // The Regular lock needs nothing chosen first.
        } else if typeSite {
            guard let field = find("websites", in: w) else { return check("\(name): found the Websites field", false) }
            click(at: field, in: w)
            type("reddit.com", in: w)
        } else {
            guard let tile = find("platform:youtube", in: w) else { return check("\(name): found the YouTube tile", false) }
            click(at: tile, in: w)
        }
        let key = regular ? "hold:Hold to start your regular lock for 1h" : "hold:Hold to lock for 1h"
        guard let button = find(key, in: w) else { return check("\(name): found the Hold to lock button", false) }
        let poke = churn ? Timer(timeInterval: 0.25, repeats: true) { _ in MainActor.assumeIsolated { model.snapshotPoke() } } : nil
        if let poke { RunLoop.main.add(poke, forMode: .common) }
        hold(at: button, in: w, seconds: holdFor)
        poke?.invalidate()
        let expected = holdFor >= 1.5 ? 1 : 0
        check("\(name): \(expected == 1 ? "holding starts a lock" : "a short press starts nothing")", model.snapshotActions == expected)
        w.close()
    }

    private static func type(_ text: String, in w: NSWindow) {
        for ch in text {
            let c = String(ch)
            for t in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: w.windowNumber, context: nil, characters: c, charactersIgnoringModifiers: c,
                                            isARepeat: false, keyCode: 0) {
                    w.sendEvent(e)
                }
            }
            pump(0.02)
        }
        pump(0.3)
    }

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        fflush(stdout)
    }

    private final class TallWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private static func window<V: View>(_ view: V, size: NSSize) -> NSWindow {
        let w = TallWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.makeKeyAndOrderFront(nil)
        pump(0.5)
        return w
    }

    private static func center(_ w: NSWindow) -> NSPoint {
        NSPoint(x: w.contentView!.bounds.midX, y: w.contentView!.bounds.midY)
    }

    private static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func send(_ type: NSEvent.EventType, _ p: NSPoint, _ w: NSWindow) {
        guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                         pressure: type == .leftMouseUp ? 0 : 1) else { return }
        w.sendEvent(e)
    }

    private static func click(at p: NSPoint, in w: NSWindow) {
        send(.leftMouseDown, p, w)
        pump(0.05)
        send(.leftMouseUp, p, w)
        pump(0.3)
    }

    private static func hold(at p: NSPoint, in w: NSWindow, seconds: Double, wiggle: Bool = false) {
        send(.leftMouseDown, p, w)
        let end = Date().addingTimeInterval(seconds)
        var i = 0
        while Date() < end {
            pump(0.1)
            if wiggle { i += 1; send(.leftMouseDragged, NSPoint(x: p.x + Double(i % 3), y: p.y), w) }
        }
        send(.leftMouseUp, p, w)
        pump(0.5)
    }

    /// The window-coordinate centre of the view tagged `harnessFrame(key)`.
    private static func find(_ key: String, in w: NSWindow) -> NSPoint? {
        guard let frame = HarnessFrames.frames[key], let host = w.contentView else { return nil }
        return host.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
    }
}
#endif

/// Where tagged views are, for the hold harness. Release builds compile the
/// tag away.
#if DEBUG
@MainActor
enum HarnessFrames {
    static var frames: [String: CGRect] = [:]
}

extension View {
    func harnessFrame(_ key: String) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            MainActor.assumeIsolated { HarnessFrames.frames[key] = frame }
        }
    }
}
#else
extension View {
    func harnessFrame(_ key: String) -> some View { self }
}
#endif
