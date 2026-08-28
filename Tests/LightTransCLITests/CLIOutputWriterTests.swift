import Foundation
import XCTest
import LightTransCore
@testable import LightTransCLI

final class CLIOutputWriterTests: XCTestCase {
    func testTextOutputUsesFixedOrderWithoutAddingBlankLine() {
        let summary = makeSummary(literalText: "literal\n", rewriteText: "rewrite")
        XCTAssertEqual(
            CLIOutputWriter.textOutput(summary: summary),
            "-直译-\nliteral\n-转写-\nrewrite\n"
        )
    }

    func testTextOutputKeepsOnlyRequestedRoute() {
        let route = TranslationRouteSummary(route: .rewrite, status: .done, text: "rewrite", failure: nil)
        let summary = TranslationSummary(
            mode: .rewrite,
            status: .done,
            model: "model",
            literal: nil,
            rewrite: route,
            history: .written
        )
        XCTAssertEqual(CLIOutputWriter.textOutput(summary: summary), "-转写-\nrewrite\n")
    }

    func testNDJSONFailureContainsStableCodeAndNoSensitiveFields() throws {
        let failure = TranslationFailure(code: .network, message: "网络连接失败，请检查网络后重试")
        let route = TranslationRouteSummary(route: .literal, status: .failed, text: "partial", failure: failure)
        let line = try XCTUnwrap(CLIOutputWriter.ndjsonLine(for: .routeFinished(route)))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["event"] as? String, "route_finished")
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? String, "network")
        XCTAssertNil(object["apiKey"])
        XCTAssertNil(object["prompt"])
        XCTAssertNil(object["historyPath"])
    }

    func testExitCodePriority() {
        let failed = makeSummary(
            literalStatus: .failed,
            literalFailure: .init(code: .network, message: "网络失败")
        )
        XCTAssertEqual(CLIOutputWriter.exitCode(summary: failed, interrupted: false, outputError: false), .routeFailed)
        XCTAssertEqual(CLIOutputWriter.exitCode(summary: failed, interrupted: false, outputError: true), .internalError)
        XCTAssertEqual(CLIOutputWriter.exitCode(summary: failed, interrupted: true, outputError: true), .interrupted)

        let unavailableRoute = TranslationRouteSummary(
            route: .literal,
            status: .failed,
            text: "",
            failure: .init(code: .configurationUnavailable, message: "配置不可用")
        )
        let unavailable = TranslationSummary(
            mode: .literal,
            status: .failed,
            model: "",
            literal: unavailableRoute,
            rewrite: nil,
            history: .failed
        )
        XCTAssertEqual(
            CLIOutputWriter.exitCode(summary: unavailable, interrupted: false, outputError: false),
            .configurationUnavailable
        )
    }

    private func makeSummary(
        literalText: String = "literal",
        rewriteText: String = "rewrite",
        literalStatus: TranslationRouteStatus = .done,
        literalFailure: TranslationFailure? = nil
    ) -> TranslationSummary {
        let literal = TranslationRouteSummary(
            route: .literal,
            status: literalStatus,
            text: literalText,
            failure: literalFailure
        )
        let rewrite = TranslationRouteSummary(
            route: .rewrite,
            status: .done,
            text: rewriteText,
            failure: nil
        )
        return TranslationSummary(
            mode: .both,
            status: literalStatus == .failed ? .failed : .done,
            model: "model",
            literal: literal,
            rewrite: rewrite,
            history: .written
        )
    }
}
