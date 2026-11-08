import NetworkExtension

final class DNSProxyProvider: NEDNSProxyProvider {
    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) { completionHandler(nil) }
    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) { completionHandler() }
    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool { false }
}
