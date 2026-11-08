import Foundation
import Network
import NetworkExtension
import ProsperCore

/// Sees every new network flow on the Mac and drops the ones the rules block
/// (PLAN.md M1.2). A flow is named, in order, by:
///
/// 1. `remoteHostname`, which Safari and anything on URLSession/Network.framework provide;
/// 2. the server name in its TLS ClientHello (Chrome, Brave, curl), read by peeking the first bytes;
/// 3. the Host header of plain HTTP;
/// 4. the DNS proxy's recent answers for its address.
///
/// A flow that stays unnamed is allowed and counted, never blocked: a
/// fail-closed filter breaks the Mac within the hour (§3.3, decision §10.7).
final class FilterDataProvider: NEFilterDataProvider {
    private let keeper = RuleKeeper.shared

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        // Look at every flow; the provider decides.
        let settings = NEFilterSettings(rules: [], defaultAction: .filterData)
        apply(settings) { error in
            if let error {
                filterLog.error("Filter settings failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self.keeper.filterStartedAt = Date()
                filterLog.info("Content filter started")
            }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        filterLog.info("Content filter stopped: \(reason.rawValue)")
        keeper.filterStartedAt = nil
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow else { return .allow() }
        let rules = keeper.current
        guard rules.guardOn || rules.hasLocks else { return .allow() }

        let isUDP = socketFlow.socketProtocol == IPPROTO_UDP
        let (address, port) = remote(of: socketFlow)

        // Inbound-initiated flows (servers on this Mac) are not browsing.
        if socketFlow.direction == .inbound { return .allow() }

        if rules.guardOn, rules.closeBypasses,
           BypassRules.verdict(isUDP: isUDP, remotePort: port, remoteAddress: address) == .block {
            keeper.countBlocked()
            return .drop()
        }

        if let host = socketFlow.remoteHostname ?? flow.url?.host, !host.isEmpty {
            return verdict(forHost: host, rules: rules)
        }

        // Unnamed TCP to a web port: read the first bytes for the server name.
        if !isUDP, port == 443 || port == 80 || port == 8443 || port == 8080 {
            return .filterDataVerdict(withFilterInbound: false, peekInboundBytes: 0, filterOutbound: true, peekOutboundBytes: 2048)
        }

        if let address, let host = keeper.host(forAddress: address) {
            return verdict(forHost: host, rules: rules)
        }
        keeper.countUnnamed()
        return .allow()
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        let rules = keeper.current
        let bytes = [UInt8](readBytes)
        var host: String?
        switch SNIParser.parse(bytes) {
        case .hostname(let name):
            host = name
        case .needMoreData where readBytes.count < SNIParser.maxPeekBytes:
            return NEFilterDataVerdict(passBytes: 0, peekBytes: SNIParser.maxPeekBytes)
        case .notTLS:
            host = Self.httpHost(bytes)
        default:
            break
        }
        if host == nil, let socketFlow = flow as? NEFilterSocketFlow, let address = remote(of: socketFlow).address {
            host = keeper.host(forAddress: address)
        }
        guard let host else {
            keeper.countUnnamed()
            return .allow()
        }
        if shouldBlock(host: host, rules: rules) {
            keeper.countBlocked()
            return .drop()
        }
        return .allow()
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        .allow()
    }

    // MARK: - Helpers

    private func verdict(forHost host: String, rules: ActiveRules) -> NEFilterNewFlowVerdict {
        if shouldBlock(host: host, rules: rules) {
            keeper.countBlocked()
            return .drop()
        }
        return .allow()
    }

    private func shouldBlock(host: String, rules: ActiveRules) -> Bool {
        if rules.reason(forHost: host) != nil { return true }
        if rules.guardOn, rules.closeBypasses, BypassRules.isBypassHost(host) { return true }
        return false
    }

    private func remote(of flow: NEFilterSocketFlow) -> (address: String?, port: Int) {
        guard let endpoint = flow.remoteFlowEndpoint else { return (nil, 0) }
        if case let .hostPort(host, port) = endpoint {
            var address: String
            switch host {
            case .ipv4(let v4): address = "\(v4)"
            case .ipv6(let v6): address = "\(v6)"
            case .name(let name, _): address = name
            @unknown default: address = "\(host)"
            }
            if let percent = address.firstIndex(of: "%") { address = String(address[..<percent]) }
            return (address, Int(port.rawValue))
        }
        return (nil, 0)
    }

    /// The Host header of a plain HTTP request, if these bytes are one.
    static func httpHost(_ bytes: [UInt8]) -> String? {
        guard let text = String(bytes: bytes.prefix(2048), encoding: .ascii),
              text.hasPrefix("GET ") || text.hasPrefix("POST ") || text.hasPrefix("HEAD ") || text.hasPrefix("PUT ") || text.hasPrefix("CONNECT ") else { return nil }
        for line in text.split(separator: "\r\n") where line.lowercased().hasPrefix("host:") {
            var host = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
            return host.lowercased()
        }
        return nil
    }
}
