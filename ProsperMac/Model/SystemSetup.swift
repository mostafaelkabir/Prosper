import AppKit
import NetworkExtension
import os.log
import ServiceManagement
import SystemExtensions

private let setupLog = Logger(subsystem: "com.mostafa.prosper.mac", category: "setup")

/// Installs and switches on the three pieces that do the work: the system
/// extension (network filter + DNS proxy) and the background agent. Each step
/// reports exactly what state it is in, so the app never says "protected"
/// when it is not (PLAN.md §7.4).
@MainActor
final class SystemSetup: NSObject, ObservableObject {
    enum StepState: Equatable {
        case unknown, working, needsApproval(String), on, off, failed(String)

        var isOn: Bool { self == .on }
    }

    @Published private(set) var extensionState: StepState = .unknown
    @Published private(set) var filterState: StepState = .unknown
    @Published private(set) var dnsState: StepState = .unknown
    @Published private(set) var agentState: StepState = .unknown

    static let extensionID = "com.mostafa.prosper.mac.filter"
    static let agentPlist = "com.mostafa.prosper.mac.agent.plist"

    var allOn: Bool { extensionState.isOn && filterState.isOn && dnsState.isOn && agentState.isOn }

    /// Reads the current state of everything without changing anything.
    func refresh() {
        refreshAgent()
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let manager = NEFilterManager.shared()
                if let error { self.filterState = .failed(error.localizedDescription) }
                else if manager.providerConfiguration == nil { self.filterState = .off }
                else { self.filterState = manager.isEnabled ? .on : .off }
            }
        }
        NEDNSProxyManager.shared().loadFromPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let manager = NEDNSProxyManager.shared()
                if let error { self.dnsState = .failed(error.localizedDescription) }
                else if manager.providerProtocol == nil { self.dnsState = .off }
                else { self.dnsState = manager.isEnabled ? .on : .off }
            }
        }
        if extensionState == .unknown, filterState == .on {
            extensionState = .on
        }
    }

    /// Runs every step that is not on yet. Safe to call repeatedly: each step
    /// only switches things on.
    func installEverything() {
        registerAgent()
        activateExtension()
    }

    // MARK: - Agent

    func registerAgent() {
        let service = SMAppService.agent(plistName: Self.agentPlist)
        do {
            if service.status != .enabled { try service.register() }
        } catch {
            setupLog.error("Agent register failed: \(error.localizedDescription, privacy: .public)")
            agentState = .failed(error.localizedDescription)
            return
        }
        refreshAgent()
    }

    private func refreshAgent() {
        switch SMAppService.agent(plistName: Self.agentPlist).status {
        case .enabled: agentState = .on
        case .requiresApproval: agentState = .needsApproval("Allow StolenEyes in System Settings → General → Login Items & Extensions.")
        case .notRegistered: agentState = .off
        case .notFound: agentState = .failed("The agent is missing from the app bundle.")
        @unknown default: agentState = .unknown
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - System extension

    func activateExtension() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            extensionState = .failed("Move StolenEyes to the Applications folder first. macOS only loads its network filter from there.")
            return
        }
        extensionState = .working
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - Filter and DNS proxy

    private func enableFilter() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] loadError in
            Task { @MainActor in
                guard let self else { return }
                if let loadError {
                    self.filterState = .failed(loadError.localizedDescription)
                    return
                }
                if manager.providerConfiguration == nil {
                    let config = NEFilterProviderConfiguration()
                    config.filterSockets = true
                    config.filterPackets = false
                    config.filterDataProviderBundleIdentifier = Self.extensionID
                    manager.providerConfiguration = config
                }
                manager.localizedDescription = "StolenEyes"
                manager.isEnabled = true
                self.filterState = .working
                manager.saveToPreferences { saveError in
                    Task { @MainActor in
                        if let saveError {
                            setupLog.error("Filter save failed: \(saveError.localizedDescription, privacy: .public)")
                            self.filterState = .failed(saveError.localizedDescription)
                        } else {
                            self.filterState = manager.isEnabled ? .on : .off
                        }
                        self.enableDNSProxy()
                    }
                }
            }
        }
    }

    private func enableDNSProxy() {
        let manager = NEDNSProxyManager.shared()
        manager.loadFromPreferences { [weak self] loadError in
            Task { @MainActor in
                guard let self else { return }
                if let loadError {
                    self.dnsState = .failed(loadError.localizedDescription)
                    return
                }
                if manager.providerProtocol == nil {
                    let proto = NEDNSProxyProviderProtocol()
                    proto.providerBundleIdentifier = Self.extensionID
                    manager.providerProtocol = proto
                }
                manager.localizedDescription = "StolenEyes"
                manager.isEnabled = true
                self.dnsState = .working
                manager.saveToPreferences { saveError in
                    Task { @MainActor in
                        if let saveError {
                            setupLog.error("DNS proxy save failed: \(saveError.localizedDescription, privacy: .public)")
                            self.dnsState = .failed(saveError.localizedDescription)
                        } else {
                            self.dnsState = manager.isEnabled ? .on : .off
                        }
                    }
                }
            }
        }
    }

    /// If someone switched the filter or DNS proxy off in System Settings,
    /// switch them back on. Called on launch and every minute while the app
    /// runs. Never the other way round: there is no code that turns them off.
    func reassert() {
        guard extensionState.isOn || filterState != .unknown else { return }
        if filterState == .off { enableFilter() } else if dnsState == .off { enableDNSProxy() }
    }
}

extension SystemSetup: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            self.extensionState = .needsApproval("Open System Settings → General → Login Items & Extensions → Network Extensions and switch StolenEyes on.")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            setupLog.info("Extension activation finished: \(result.rawValue)")
            self.extensionState = .on
            self.enableFilter()
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            setupLog.error("Extension activation failed: \(error.localizedDescription, privacy: .public)")
            self.extensionState = .failed(error.localizedDescription)
        }
    }
}
