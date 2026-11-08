import Foundation
import ObjectiveC
import Testing
import ProsperCore

/// PLAN.md M4.5 and §7: no message to the extension can end a lock or
/// switch off the guard. This enumerates the XPC protocol at runtime, so a
/// new message fails here until someone has looked at it.
struct NoCancelAuditTests {
    @Test("The filter's XPC protocol has exactly the three safe messages")
    func xpcProtocol() {
        var count: UInt32 = 0
        let proto: Protocol = FilterControl.self
        guard let list = protocol_copyMethodDescriptionList(proto, true, true, &count) else {
            Issue.record("No methods found")
            return
        }
        defer { free(list) }
        let names = Set((0..<Int(count)).compactMap { list[$0].name.map(NSStringFromSelector) })
        #expect(names == ["applyWithRules:reply:", "statusWithReply:", "rulesWithReply:"])
    }

    @Test("Applying a document with every lock removed changes nothing")
    func emptyDocumentChangesNothing() throws {
        let now = Date()
        let (rules, _) = try RulesBook.startingSession(RulesBook.enablingGuard(.empty, now: now), minutes: 30, domains: ["youtube.com"], bundleIDs: [], platformIDs: [], now: now)
        let afterEmpty = rules.merged(with: .empty, at: now)
        #expect(rules.isPreserved(by: afterEmpty, at: now))
        #expect(afterEmpty.guardState != nil)
    }
}
