import Foundation
import ProsperCore

/// The extension's XPC listener (PLAN.md M1.4). Only processes signed by our
/// team can connect, and the two messages it understands cannot remove
/// anything (`FilterControl`).
final class FilterService: NSObject, NSXPCListenerDelegate, FilterControl {
    static let shared = FilterService()
    private var listener: NSXPCListener?

    func start() {
        let listener = NSXPCListener(machServiceName: FilterXPC.machServiceName)
        listener.setConnectionCodeSigningRequirement(FilterXPC.clientRequirement)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        filterLog.info("XPC listener started on \(FilterXPC.machServiceName, privacy: .public)")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FilterControl.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func apply(rules: Data, reply: @escaping (Data?) -> Void) {
        guard let incoming = try? MacStore.decoder.decode(MacRules.self, from: rules) else {
            filterLog.error("Ignored rules that did not decode")
            reply(try? MacStore.encoder.encode(RuleKeeper.shared.status()))
            return
        }
        let status = RuleKeeper.shared.apply(incoming)
        reply(try? MacStore.encoder.encode(status))
    }

    func status(reply: @escaping (Data?) -> Void) {
        reply(try? MacStore.encoder.encode(RuleKeeper.shared.status()))
    }

    func rules(reply: @escaping (Data?) -> Void) {
        reply(try? MacStore.encoder.encode(RuleKeeper.shared.document))
    }
}
