#if os(macOS)
import Foundation

/// Talks to the system extension over XPC. Every call has a timeout and
/// failures are reported, never assumed away: an extension that does not
/// answer shows in red in the app.
public final class FilterClient: @unchecked Sendable {
    public init() {}

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private func proxy(_ onError: @escaping (Error) -> Void) -> FilterControl? {
        lock.lock()
        defer { lock.unlock() }
        if connection == nil {
            let c = NSXPCConnection(machServiceName: FilterXPC.machServiceName, options: [])
            c.remoteObjectInterface = NSXPCInterface(with: FilterControl.self)
            c.invalidationHandler = { [weak self] in
                self?.lock.lock()
                self?.connection = nil
                self?.lock.unlock()
            }
            c.interruptionHandler = { [weak self] in
                self?.lock.lock()
                self?.connection?.invalidate()
                self?.connection = nil
                self?.lock.unlock()
            }
            c.resume()
            connection = c
        }
        return connection?.remoteObjectProxyWithErrorHandler(onError) as? FilterControl
    }

    /// Sends the rules; replies with the extension's status, or an error text.
    public func apply(_ rules: MacRules, completion: @escaping (Result<FilterStatus, Error>) -> Void) {
        guard let data = try? MacStore.encoder.encode(rules) else { return }
        call(completion) { proxy, reply in proxy.apply(rules: data, reply: reply) }
    }

    public func status(completion: @escaping (Result<FilterStatus, Error>) -> Void) {
        call(completion) { proxy, reply in proxy.status(reply: reply) }
    }

    public func rules(completion: @escaping (MacRules?) -> Void) {
        let once = OnceFlag()
        guard let proxy = proxy({ _ in if once.take() { completion(nil) } }) else { completion(nil); return }
        proxy.rules { data in
            guard once.take() else { return }
            completion(data.flatMap { try? MacStore.decoder.decode(MacRules.self, from: $0) })
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if once.take() { completion(nil) } }
    }

    private func call(_ completion: @escaping (Result<FilterStatus, Error>) -> Void, _ body: (FilterControl, @escaping (Data?) -> Void) -> Void) {
        let once = OnceFlag()
        let fail: (Error) -> Void = { error in if once.take() { completion(.failure(error)) } }
        guard let proxy = proxy(fail) else {
            fail(FilterClientError.unavailable)
            return
        }
        body(proxy) { data in
            guard once.take() else { return }
            if let data, let status = try? MacStore.decoder.decode(FilterStatus.self, from: data) {
                completion(.success(status))
            } else {
                completion(.failure(FilterClientError.badReply))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { fail(FilterClientError.timeout) }
    }
}

public enum FilterClientError: LocalizedError {
    case unavailable, badReply, timeout
    public var errorDescription: String? {
        switch self {
        case .unavailable: "The network filter is not installed or not running."
        case .badReply: "The network filter answered with something unreadable."
        case .timeout: "The network filter did not answer."
        }
    }
}

public final class OnceFlag: @unchecked Sendable {
    public init() {}
    private let lock = NSLock()
    private var taken = false
    public func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
#endif
