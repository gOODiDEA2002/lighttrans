import Foundation
import XCTest
@testable import LightTransCLI

final class CLIInputReaderTests: XCTestCase {
    func testPositionArgumentsJoinWithOneSpaceAndPreserveContent() throws {
        let result = try CLIInputReader.readInput(
            textArguments: ["  第一段", "第二段\n"],
            isStandardInputTerminal: true
        )
        XCTAssertEqual(result, "  第一段 第二段\n")
    }

    func testReadsPipedInputVerbatim() throws {
        let input = "  第一行\n第二行\n"
        let result = try CLIInputReader.readInput(
            textArguments: [],
            isStandardInputTerminal: false,
            readStandardInput: { Data(input.utf8) }
        )
        XCTAssertEqual(result, input)
    }

    func testRejectsPositionArgumentsAndPipedInputConflict() {
        XCTAssertThrowsError(try CLIInputReader.readInput(
            textArguments: ["text"],
            isStandardInputTerminal: false,
            readStandardInput: { Data("pipe".utf8) }
        )) { error in
            guard case CLIInputError.conflict = error else {
                return XCTFail("应返回输入冲突")
            }
        }
    }

    func testRejectsWhitespaceOnlyInput() {
        XCTAssertThrowsError(try CLIInputReader.readInput(
            textArguments: [],
            isStandardInputTerminal: false,
            readStandardInput: { Data(" \n\t".utf8) }
        )) { error in
            guard case CLIInputError.empty = error else {
                return XCTFail("应返回空输入")
            }
        }
    }
}
