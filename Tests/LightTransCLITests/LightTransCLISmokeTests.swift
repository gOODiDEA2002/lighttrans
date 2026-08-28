import XCTest
@testable import LightTransCLI

final class LightTransCLISmokeTests: XCTestCase {
    func testParseDefaultOptions() {
        let parsed = CLIOptionsParser.parse(arguments: [])
        guard case .run(let options) = parsed else {
            XCTFail("应返回 run")
            return
        }
        XCTAssertEqual(options.mode, .both)
        XCTAssertEqual(options.format, .text)
    }
}
