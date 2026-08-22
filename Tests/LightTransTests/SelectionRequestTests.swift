import XCTest
import AppKit
@testable import LightTrans

final class SelectionRequestTests: XCTestCase {
    func testOpenPanelReportsMissingPlainText() {
        let provider = SelectionServiceProvider()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-selection-missing-\(UUID().uuidString)"))
        pasteboard.clearContents()

        var serviceError: NSString?
        provider.openPanelWithSelectedText(pasteboard, userData: nil, error: &serviceError)

        XCTAssertEqual(serviceError, "未收到可处理的文本")
    }

    func testOpenPanelRejectsWhitespaceOnlySelection() {
        let provider = SelectionServiceProvider()
        var capturedRequest: SelectionRequest?
        provider.onRequest = { request in
            capturedRequest = request
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-selection-whitespace-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(" \n\t ", forType: .string)

        var serviceError: NSString?
        provider.openPanelWithSelectedText(pasteboard, userData: nil, error: &serviceError)

        XCTAssertNil(capturedRequest)
        XCTAssertNil(serviceError)
    }

    func testOpenPanelPreservesRawSelectionText() async {
        let provider = SelectionServiceProvider()
        let expectation = expectation(description: "receive request")
        var capturedRequest: SelectionRequest?
        provider.onRequest = { request in
            capturedRequest = request
            expectation.fulfill()
        }

        let rawText = "  首行 e\u{301}\n第二行🙂中 English\n  "
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-selection-raw-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(rawText, forType: .string)

        var serviceError: NSString?
        provider.openPanelWithSelectedText(pasteboard, userData: nil, error: &serviceError)
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertNil(serviceError)
        XCTAssertEqual(capturedRequest?.text, rawText)
    }
}
