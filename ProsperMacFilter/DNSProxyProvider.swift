import Foundation
import Network
import NetworkExtension
import ProsperCore

/// Answers every DNS query on the Mac (PLAN.md M1.3).
///
/// - Names behind the guard, and the bypass hosts it closes, get NXDOMAIN.
/// - Sites under a running lock get NXDOMAIN too, so they fail fast; the
///   content filter blocks them regardless.
/// - While the guard is on, Google, Bing, DuckDuckGo and YouTube resolve to
///   their forced-safe hosts, and HTTPS/SVCB records are answered empty so no
///   browser negotiates Encrypted ClientHello.
/// - Everything else goes, unchanged, to the server the query was sent to.
///   That keeps whatever DNS the Mac already uses (Wi-Fi, VPN, Tailscale).
///
/// Every failure forwards rather than drops: a broken DNS proxy is a broken Mac.
final class DNSProxyProvider: NEDNSProxyProvider, NEAppProxyUDPFlowHandling {
    private let keeper = RuleKeeper.shared
    private let queue = DispatchQueue(label: "com.mostafa.prosper.mac.filter.dns", qos: .userInitiated, attributes: .concurrent)

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        keeper.dnsStartedAt = Date()
        filterLog.info("DNS proxy started")
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        filterLog.info("DNS proxy stopped: \(reason.rawValue)")
        keeper.dnsStartedAt = nil
        completionHandler()
    }

    func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow, initialRemoteFlowEndpoint remoteEndpoint: Network.NWEndpoint) -> Bool {
        openUDP(flow)
        return true
    }

    private func openUDP(_ flow: NEAppProxyUDPFlow) {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            if let error {
                filterLog.error("DNS flow open failed: \(error.localizedDescription, privacy: .public)")
                flow.closeReadWithError(error)
                flow.closeWriteWithError(error)
                return
            }
            self.readLoop(flow)
        }
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // UDP normally arrives through handleNewUDPFlow above.
        if let udp = flow as? NEAppProxyUDPFlow {
            openUDP(udp)
            return true
        }
        // DNS over TCP (large answers): passed through untouched.
        guard let tcp = flow as? NEAppProxyTCPFlow else { return false }
        guard case let .hostPort(host, port) = tcp.remoteFlowEndpoint else { return false }
        let connection = NWConnection(host: host, port: port, using: .tcp)
        tcp.open(withLocalFlowEndpoint: nil) { error in
            if let error {
                tcp.closeReadWithError(error)
                tcp.closeWriteWithError(error)
                return
            }
            TCPPipe(flow: tcp, connection: connection, queue: self.queue).start()
        }
        return true
    }

    // MARK: - UDP

    private func readLoop(_ flow: NEAppProxyUDPFlow) {
        flow.readDatagrams { [weak self] datagrams, error in
            guard let self else { return }
            guard error == nil, let datagrams, !datagrams.isEmpty else {
                flow.closeReadWithError(nil)
                flow.closeWriteWithError(nil)
                return
            }
            for (data, endpoint) in datagrams {
                self.queue.async {
                    self.answer(query: data, to: endpoint) { reply in
                        guard let reply else { return }
                        flow.writeDatagrams([(reply, endpoint)]) { _ in }
                    }
                }
            }
            self.readLoop(flow)
        }
    }

    private func answer(query data: Data, to server: Network.NWEndpoint, reply: @escaping (Data?) -> Void) {
        let bytes = [UInt8](data)
        guard let message = DNSMessage.parse(bytes), let question = message.questions.first else {
            forward(data, to: server, reply: reply)
            return
        }
        let rules = keeper.current
        let host = question.name

        if let reason = rules.reason(forHost: host) {
            keeper.countBlocked()
            _ = reason
            reply(DNSMessage.nxdomain(for: bytes).map { Data($0) })
            return
        }
        guard rules.guardOn else {
            forward(data, to: server, recordingFor: host, reply: reply)
            return
        }
        if rules.closeBypasses, BypassRules.isBypassHost(host) {
            keeper.countBlocked()
            reply(DNSMessage.nxdomain(for: bytes).map { Data($0) })
            return
        }
        if rules.closeBypasses, question.type == DNSQuestion.typeHTTPS || question.type == DNSQuestion.typeSVCB {
            reply(DNSMessage.empty(for: bytes).map { Data($0) })
            return
        }
        if rules.safeSearch, let target = SafeSearch.target(for: host) {
            guard question.type == DNSQuestion.typeA || question.type == DNSQuestion.typeAAAA,
                  let renamed = DNSMessage.query(bytes, renamedTo: target) else {
                reply(DNSMessage.empty(for: bytes).map { Data($0) })
                return
            }
            keeper.countSafeSearch()
            forward(Data(renamed), to: server) { upstream in
                guard let upstream, let parsed = DNSMessage.parse([UInt8](upstream)),
                      let rewritten = DNSMessage.addresses(for: bytes, records: parsed.answers) else {
                    // Could not resolve the safe host: refuse rather than fall back to unsafe results.
                    reply(DNSMessage.empty(for: bytes).map { Data($0) })
                    return
                }
                reply(Data(rewritten))
            }
            return
        }
        forward(data, to: server, recordingFor: host, reply: reply)
    }

    /// Sends the query to `server` and hands back its answer (nil after 5 s).
    private func forward(_ query: Data, to server: Network.NWEndpoint, recordingFor host: String? = nil, reply: @escaping (Data?) -> Void) {
        guard case let .hostPort(serverHost, serverPort) = server else {
            reply(nil)
            return
        }
        let connection = NWConnection(host: serverHost, port: serverPort, using: .udp)
        let once = Once()
        let finish: (Data?) -> Void = { data in
            guard once.run() else { return }
            connection.cancel()
            reply(data)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: query, completion: .contentProcessed { error in
                    if error != nil { finish(nil) }
                })
                connection.receiveMessage { data, _, _, error in
                    if let data, let host { self.recordAnswers(data, host: host) }
                    finish(error == nil ? data : nil)
                }
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { finish(nil) }
    }

    private func recordAnswers(_ data: Data, host: String) {
        guard let message = DNSMessage.parse([UInt8](data)) else { return }
        let addresses = message.answers.compactMap(\.address)
        let ttl = message.answers.map(\.ttl).min() ?? 300
        keeper.remember(host: host, addresses: addresses, ttl: ttl)
    }
}

/// Runs a closure's work exactly once across threads.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Copies bytes both ways between an intercepted TCP flow and its real server.
final class TCPPipe: @unchecked Sendable {
    let flow: NEAppProxyTCPFlow
    let connection: NWConnection
    let queue: DispatchQueue

    init(flow: NEAppProxyTCPFlow, connection: NWConnection, queue: DispatchQueue) {
        self.flow = flow
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                flowToServer()
                serverToFlow()
            case .failed, .cancelled:
                flow.closeReadWithError(nil)
                flow.closeWriteWithError(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func flowToServer() {
        flow.readData { [self] data, error in
            guard let data, !data.isEmpty, error == nil else {
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
                return
            }
            connection.send(content: data, completion: .contentProcessed { [self] error in
                if error == nil { flowToServer() } else { connection.cancel() }
            })
        }
    }

    private func serverToFlow() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                flow.write(data) { [self] writeError in
                    if writeError == nil, !isComplete, error == nil { serverToFlow() } else { finish() }
                }
            } else {
                finish()
            }
        }
    }

    private func finish() {
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
        connection.cancel()
    }
}
