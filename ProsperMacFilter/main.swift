import Foundation
import NetworkExtension

// One process hosts both providers and the XPC listener, so the DNS proxy's
// address map and the rules are shared in memory.
autoreleasepool {
    NEProvider.startSystemExtensionMode()
    FilterService.shared.start()
}
dispatchMain()
