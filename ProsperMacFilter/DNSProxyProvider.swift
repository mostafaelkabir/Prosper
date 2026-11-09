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
        // DNS over TCP: the same rules per query; the rest goes to the server
        // over TCP, since that is why the client used TCP (large answers).
        guard let tcp = flow as? NEAppProxyTCPFlow else { return false }
        guard case let .hostPort(host, port) = tcp.remoteFlowEndpoint else { return false }
        let connection = NWConnection(host: host, port: port, using: .tcp)
        tcp.open(withLocalFlowEndpoint: nil) { error in
            if let error {
                tcp.closeReadWithError(error)
                tcp.closeWriteWithError(error)
                return
            }
            let server = tcp.remoteFlowEndpoint
            TCPPipe(flow: tcp, connection: connection, queue: self.queue) { [weak self] query, local in
                guard let self else { return false }
                switch self.decide(query) {
                case .forward:
                    return false
                case .reply(let reply):
                    local(reply)
                case .safeSearch(let target):
                    self.resolveSafe(query, target: target, server: server) { reply in
                        local(reply.map { [UInt8]($0) } ?? DNSMessage.empty(for: query) ?? [])
                    }
                }
                return true
            }.start()
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

    /// What the proxy does with one query. Shared by UDP and DNS over TCP.
    private enum Decision {
        case reply([UInt8])
        case safeSearch(target: String)
        case forward(host: String?)
    }

    private func decide(_ bytes: [UInt8]) -> Decision {
        guard let message = DNSMessage.parse(bytes), let question = message.questions.first else {
            return .forward(host: nil)
        }
        let rules = keeper.current
        let host = question.name
        let nxdomain = DNSMessage.nxdomain(for: bytes)
        let empty = DNSMessage.empty(for: bytes)

        if rules.reason(forHost: host) != nil, let nxdomain {
            keeper.countBlocked()
            return .reply(nxdomain)
        }
        guard rules.guardOn else { return .forward(host: host) }
        if rules.closeBypasses, BypassRules.isBypassHost(host), let nxdomain {
            keeper.countBlocked()
            return .reply(nxdomain)
        }
        if rules.closeBypasses, question.type == DNSQuestion.typeHTTPS || question.type == DNSQuestion.typeSVCB, let empty {
            return .reply(empty)
        }
        if rules.safeSearch, let target = SafeSearch.target(for: host) {
            guard question.type == DNSQuestion.typeA || question.type == DNSQuestion.typeAAAA else {
                return empty.map(Decision.reply) ?? .forward(host: host)
            }
            return .safeSearch(target: target)
        }
        return .forward(host: host)
    }

    private func answer(query data: Data, to server: Network.NWEndpoint, reply: @escaping (Data?) -> Void) {
        let bytes = [UInt8](data)
        switch decide(bytes) {
        case .reply(let local):
            reply(Data(local))
        case .forward(let host):
            forward(data, to: server, recordingFor: host, reply: reply)
        case .safeSearch(let target):
            resolveSafe(bytes, target: target, server: server, reply: reply)
        }
    }

    /// Resolves the forced-safe host and answers under the asked name.
    private func resolveSafe(_ bytes: [UInt8], target: String, server: Network.NWEndpoint, reply: @escaping (Data?) -> Void) {
        guard let renamed = DNSMessage.query(bytes, renamedTo: target) else {
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

/// Carries DNS over TCP between an intercepted flow and its real server.
/// Each length-prefixed query is offered to `intercept` first; when it answers
/// locally the query never reaches the server. Clients match TCP answers by
/// ID, so local and server answers may arrive in any order (RFC 7766).
final class TCPPipe: @unchecked Sendable {
    typealias Intercept = (_ query: [UInt8], _ answer: @escaping ([UInt8]) -> Void) -> Bool

    let flow: NEAppProxyTCPFlow
    let connection: NWConnection
    let queue: DispatchQueue
    let intercept: Intercept
    private var pending: [UInt8] = []
    private var writes: [(bytes: [UInt8], done: ((Bool) -> Void)?)] = []
    private var writing = false
    private let lock = NSLock()

    init(flow: NEAppProxyTCPFlow, connection: NWConnection, queue: DispatchQueue, intercept: @escaping Intercept) {
        self.flow = flow
        self.connection = connection
        self.queue = queue
        self.intercept = intercept
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
            pending += data
            var toServer: [UInt8] = []
            while pending.count >= 2 {
                let length = Int(pending[0]) << 8 | Int(pending[1])
                guard pending.count >= 2 + length else { break }
                let query = Array(pending[2..<(2 + length)])
                pending.removeFirst(2 + length)
                let handled = intercept(query) { [self] answer in
                    writeToFlow([UInt8(answer.count >> 8), UInt8(answer.count & 0xFF)] + answer)
                }
                if !handled { toServer += [UInt8(length >> 8), UInt8(length & 0xFF)] + query }
            }
            guard !toServer.isEmpty else {
                flowToServer()
                return
            }
            connection.send(content: Data(toServer), completion: .contentProcessed { [self] error in
                if error == nil { flowToServer() } else { connection.cancel() }
            })
        }
    }

    private func serverToFlow() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                writeToFlow([UInt8](data)) { [self] ok in
                    if ok, !isComplete, error == nil { serverToFlow() } else { finish() }
                }
            } else {
                finish()
            }
        }
    }

    /// One write at a time, in order, so a local answer never lands inside a
    /// server answer.
    private func writeToFlow(_ bytes: [UInt8], done: ((Bool) -> Void)? = nil) {
        lock.lock()
        writes.append((bytes, done))
        let start = !writing
        writing = true
        lock.unlock()
        if start { writeNext() }
    }

    private func writeNext() {
        lock.lock()
        guard !writes.isEmpty else {
            writing = false
            lock.unlock()
            return
        }
        let (bytes, done) = writes.removeFirst()
        lock.unlock()
        flow.write(Data(bytes)) { [self] error in
            done?(error == nil)
            writeNext()
        }
    }

    private func finish() {
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
        connection.cancel()
    }
}
