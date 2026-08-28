import XCTest
import LightTransCore
@testable import LightTransCLI

final class CLIOptionsParserTests: XCTestCase {
    func testParsesModeAndFormatWithEqualsSyntax() {
        let result = CLIOptionsParser.parse(arguments: ["--mode=literal", "--format=json", "hello"])
        guard case .run(let options) = result else {
            XCTFail("应返回 run")
            return
        }
        XCTAssertEqual(options.mode, .literal)
        XCTAssertEqual(options.format, .json)
        XCTAssertEqual(options.textArguments, ["hello"])
    }

    func testParsesDoubleDashAsTextSeparator() {
        let result = CLIOptionsParser.parse(arguments: ["--mode", "rewrite", "--", "--help", "--not-option"])
        guard case .run(let options) = result else {
            XCTFail("应返回 run")
            return
        }
        XCTAssertEqual(options.mode, .rewrite)
        XCTAssertEqual(options.textArguments, ["--help", "--not-option"])
    }

    func testRejectsUnknownOption() {
        let result = CLIOptionsParser.parse(arguments: ["--unknown"])
        guard case .usageError = result else {
            XCTFail("未知参数应报错")
            return
        }
    }

    func testRejectsRepeatedMode() {
        let result = CLIOptionsParser.parse(arguments: ["--mode", "both", "--mode", "literal"])
        guard case .usageError = result else {
            XCTFail("重复 mode 应报错")
            return
        }
    }
}
