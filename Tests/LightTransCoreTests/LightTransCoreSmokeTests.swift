import XCTest
@testable import LightTransCore

final class LightTransCoreSmokeTests: XCTestCase {
    func testModeRoutes() {
        XCTAssertEqual(TranslationMode.literal.routes, [.literal])
        XCTAssertEqual(TranslationMode.rewrite.routes, [.rewrite])
        XCTAssertEqual(TranslationMode.both.routes, [.literal, .rewrite])
    }
}
