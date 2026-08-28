import XCTest
import LightTransCore
@testable import LightTrans

final class PanelExternalInputTests: XCTestCase {
    @MainActor
    func testSelectionAutoTranslateCharacterLimitBoundaries() async {
        let tracker = WorkflowTracker()
        let viewModel = makeViewModel(tracker: tracker)

        viewModel.acceptExternalText(String(repeating: "a", count: 4_999))
        let started4_999 = await waitUntil(timeout: 1.0) {
            (await tracker.startedRequests()).contains(String(repeating: "a", count: 4_999))
        }
        XCTAssertTrue(started4_999)
        XCTAssertNil(viewModel.selectionNotice)

        viewModel.acceptExternalText(String(repeating: "a", count: 5_001))
        let loaded = await waitUntil(timeout: 1.0) {
            viewModel.inputText.count == 5_001 && viewModel.selectionNotice != nil
        }
        XCTAssertTrue(loaded)
        let startedRequests = await tracker.startedRequests()
        XCTAssertFalse(startedRequests.contains(String(repeating: "a", count: 5_001)))

        viewModel.acceptExternalText(String(repeating: "b", count: 5_000))
        let started = await waitUntil(timeout: 1.0) {
            viewModel.literalState != .idle && viewModel.rewriteState != .idle
        }
        XCTAssertTrue(started)
        XCTAssertNil(viewModel.selectionNotice)
    }

    @MainActor
    func testWorkflowEventsDriveResultAndState() async {
        let tracker = WorkflowTracker()
        let viewModel = makeViewModel(tracker: tracker)
        viewModel.inputText = "hello"
        viewModel.startTranslate()

        let finished = await waitUntil(timeout: 1.0) {
            viewModel.literalState == .done && viewModel.rewriteState == .done
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.literalResult, "直译片段")
        XCTAssertEqual(viewModel.rewriteResult, "转写片段")
    }

    @MainActor
    func testNewestSelectionWaitsOldTaskFinished() async {
        let tracker = WorkflowTracker()
        let viewModel = makeViewModel(tracker: tracker)

        viewModel.acceptExternalText("first")
        let firstStarted = await waitUntil(timeout: 1.0) {
            (try? await tracker.startOrder(for: "first")) != nil
        }
        XCTAssertTrue(firstStarted)

        viewModel.acceptExternalText("second")
        let secondStarted = await waitUntil(timeout: 2.0) {
            (try? await tracker.startOrder(for: "second")) != nil
        }
        XCTAssertTrue(secondStarted)

        let firstFinished = try! await tracker.finishOrder(for: "first")
        let secondStart = try! await tracker.startOrder(for: "second")
        XCTAssertLessThan(firstFinished, secondStart)
        XCTAssertEqual(viewModel.inputText, "second")
    }

    @MainActor
    func testRapidSelectionRequestsOnlyStartLatestWaitingRequest() async {
        let tracker = WorkflowTracker()
        let viewModel = makeViewModel(tracker: tracker)

        viewModel.acceptExternalText("first")
        let firstStarted = await waitUntil(timeout: 1.0) {
            (await tracker.startedRequests()).contains("first")
        }
        XCTAssertTrue(firstStarted)

        viewModel.acceptExternalText("second")
        viewModel.acceptExternalText("third")
        let thirdStarted = await waitUntil(timeout: 2.0) {
            (await tracker.startedRequests()).contains("third")
        }
        XCTAssertTrue(thirdStarted)
        let requests = await tracker.startedRequests()
        XCTAssertFalse(requests.contains("second"))
        XCTAssertEqual(viewModel.inputText, "third")
    }

    @MainActor
    func testSingleRouteFailureKeepsOtherRouteResult() async {
        let viewModel = PanelViewModel { request, emit in
            await emit(.started(mode: request.mode, model: "test-model"))
            let literal = TranslationRouteSummary(
                route: .literal,
                status: .failed,
                text: "",
                failure: TranslationError.network("单路失败").failure
            )
            let rewrite = TranslationRouteSummary(
                route: .rewrite,
                status: .done,
                text: "可用转写",
                failure: nil
            )
            await emit(.routeFinished(literal))
            await emit(.chunk(route: .rewrite, text: rewrite.text))
            await emit(.routeFinished(rewrite))
            let summary = TranslationSummary(
                mode: .both,
                status: .failed,
                model: "test-model",
                literal: literal,
                rewrite: rewrite,
                history: .written
            )
            await emit(.finished(summary))
            return summary
        }
        viewModel.inputText = "single-failure"
        viewModel.startTranslate()

        let finished = await waitUntil(timeout: 1.0) {
            if case .failed = viewModel.literalState {
                return viewModel.rewriteState == .done
            }
            return false
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.rewriteResult, "可用转写")
    }

    @MainActor
    func testStopTranslateMapsToStoppedState() async {
        let tracker = WorkflowTracker()
        let viewModel = makeViewModel(tracker: tracker)
        viewModel.acceptExternalText("first")
        let started = await waitUntil(timeout: 1.0) {
            viewModel.literalState == .translating || viewModel.rewriteState == .translating
        }
        XCTAssertTrue(started)

        viewModel.stopTranslate()
        let stopped = await waitUntil(timeout: 1.0) {
            viewModel.literalState == .stopped && viewModel.rewriteState == .stopped
        }
        XCTAssertTrue(stopped)
    }

    @MainActor
    private func makeViewModel(tracker: WorkflowTracker) -> PanelViewModel {
        PanelViewModel { request, emit in
            await tracker.recordStart(text: request.text)
            await emit(.started(mode: request.mode, model: "test-model"))

            if request.text == "first" {
                await emit(.chunk(route: .literal, text: "旧任务片段"))
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                let literal = TranslationRouteSummary(route: .literal, status: .stopped, text: "旧任务片段", failure: nil)
                let rewrite = TranslationRouteSummary(route: .rewrite, status: .stopped, text: "", failure: nil)
                await emit(.routeFinished(literal))
                await emit(.routeFinished(rewrite))
                let summary = TranslationSummary(
                    mode: request.mode,
                    status: .stopped,
                    model: "test-model",
                    literal: literal,
                    rewrite: rewrite,
                    history: .written
                )
                await emit(.finished(summary))
                await tracker.recordFinish(text: request.text)
                return summary
            }

            let literal = TranslationRouteSummary(route: .literal, status: .done, text: "直译片段", failure: nil)
            let rewrite = TranslationRouteSummary(route: .rewrite, status: .done, text: "转写片段", failure: nil)
            await emit(.chunk(route: .literal, text: literal.text))
            await emit(.chunk(route: .rewrite, text: rewrite.text))
            await emit(.routeFinished(literal))
            await emit(.routeFinished(rewrite))
            let summary = TranslationSummary(
                mode: request.mode,
                status: .done,
                model: "test-model",
                literal: literal,
                rewrite: rewrite,
                history: .written
            )
            await emit(.finished(summary))
            await tracker.recordFinish(text: request.text)
            return summary
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }
}

actor WorkflowTracker {
    private var order: Int = 0
    private var startByText: [String: Int] = [:]
    private var finishByText: [String: Int] = [:]

    func recordStart(text: String) {
        order += 1
        startByText[text] = order
    }

    func recordFinish(text: String) {
        order += 1
        finishByText[text] = order
    }

    func startedRequests() -> [String] {
        Array(startByText.keys).sorted()
    }

    func startOrder(for text: String) throws -> Int {
        guard let order = startByText[text] else {
            throw NSError(domain: "tracker", code: 1)
        }
        return order
    }

    func finishOrder(for text: String) throws -> Int {
        guard let order = finishByText[text] else {
            throw NSError(domain: "tracker", code: 2)
        }
        return order
    }
}
