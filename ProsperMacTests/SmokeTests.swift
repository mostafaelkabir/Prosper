import XCTest
@testable import ProsperCore

final class SmokeTests: XCTestCase {
    func testCoreLinks() { XCTAssertFalse(MacCopy.appName.isEmpty) }
}
