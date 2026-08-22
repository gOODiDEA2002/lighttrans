import XCTest
import Foundation
@testable import LightTrans

final class PanelExternalInputTests: XCTestCase {
    @MainActor
    func testSelectionAutoTranslateCharacterLimitBoundaries() async {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        let text4_999 = String(repeating: "a", count: 4_999)
        viewModel.acceptExternalText(text4_999)
        let didComplete4_999 = await waitUntil(timeout: 1.0) {
            tracker.translateCallCount(for: "a", count: 4_999) == 2 &&
            tracker.historyRecord(forInput: text4_999)?.status == "done"
        }
        XCTAssertTrue(didComplete4_999)
        XCTAssertNil(viewModel.selectionNotice)

        let text5_000 = String(repeating: "b", count: 5_000)
        viewModel.acceptExternalText(text5_000)
        let didComplete5_000 = await waitUntil(timeout: 1.0) {
            tracker.translateCallCount(for: "b", count: 5_000) == 2 &&
            tracker.historyRecord(forInput: text5_000)?.status == "done"
        }
        XCTAssertTrue(didComplete5_000)
        XCTAssertNil(viewModel.selectionNotice)

        viewModel.acceptExternalText(String(repeating: "c", count: 5_001))
        let didLoad5_001 = await waitUntil(timeout: 1.0) {
            viewModel.inputText.count == 5_001 && viewModel.selectionNotice != nil
        }
        XCTAssertTrue(didLoad5_001)
        XCTAssertEqual(viewModel.inputText.count, 5_001)
        XCTAssertEqual(viewModel.selectionNotice, "选中文字超过 5,000 字符，请确认后翻译")
        XCTAssertEqual(tracker.translateCallCount(for: "c", count: 5_001), 0)
        XCTAssertNil(tracker.historyRecord(forInput: String(repeating: "c", count: 5_001)))
    }

    @MainActor
    func testNewestSelectionWinsAndOldTaskWritesStoppedBeforeRestart() async throws {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        viewModel.acceptExternalText("first")
        let didStartFirst = await waitUntil(timeout: 1.0) {
            tracker.translateStartCount(text: "first") == 2
        }
        XCTAssertTrue(didStartFirst)

        viewModel.acceptExternalText("second")
        let didFinishReplacement = await waitUntil(timeout: 2.0) {
            tracker.historyRecord(forInput: "first")?.status == "stopped" &&
            tracker.historyRecord(forInput: "second")?.status == "done"
        }
        XCTAssertTrue(didFinishReplacement)

        let firstStoppedOrder = try XCTUnwrap(tracker.historyRecord(forInput: "first")?.order)
        let secondTranslateOrder = try XCTUnwrap(tracker.firstTranslateOrder(text: "second"))
        XCTAssertLessThan(firstStoppedOrder, secondTranslateOrder)
        XCTAssertEqual(viewModel.inputText, "second")
    }

    @MainActor
    func testRapidSelectionRequestsOnlyStartLatestWaitingRequest() async throws {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        viewModel.acceptExternalText("first")
        let didStartFirst = await waitUntil(timeout: 1.0) {
            tracker.translateStartCount(text: "first") == 2
        }
        XCTAssertTrue(didStartFirst)

        viewModel.acceptExternalText("second")
        viewModel.acceptExternalText("third")
        let didFinishLatest = await waitUntil(timeout: 2.0) {
            tracker.historyRecord(forInput: "first")?.status == "stopped" &&
            tracker.historyRecord(forInput: "third")?.status == "done"
        }
        XCTAssertTrue(didFinishLatest)

        let firstStoppedOrder = try XCTUnwrap(tracker.historyRecord(forInput: "first")?.order)
        let thirdTranslateOrder = try XCTUnwrap(tracker.firstTranslateOrder(text: "third"))
        XCTAssertLessThan(firstStoppedOrder, thirdTranslateOrder)
        XCTAssertEqual(tracker.translateStartCount(text: "second"), 0)
        XCTAssertNil(tracker.historyRecord(forInput: "second"))
        XCTAssertEqual(viewModel.inputText, "third")
    }

    @MainActor
    func testExternalReplacementOverridesEarlierPartFailureAsStopped() async {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        viewModel.acceptExternalText("partial-first")
        let didReachPartialFailure = await waitUntil(timeout: 1.0) {
            if case .failed = viewModel.literalState {
                return viewModel.rewriteState == .translating
            }
            return false
        }
        XCTAssertTrue(didReachPartialFailure)

        viewModel.acceptExternalText("partial-second")
        let didFinishReplacement = await waitUntil(timeout: 2.0) {
            tracker.historyRecord(forInput: "partial-first")?.status == "stopped" &&
            tracker.historyRecord(forInput: "partial-second")?.status == "done"
        }
        XCTAssertTrue(didFinishReplacement)
    }

    @MainActor
    func testDisablingHistoryBeforeCancellationPreventsWrite() async {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        viewModel.acceptExternalText("toggle-history")
        let didStart = await waitUntil(timeout: 1.0) {
            tracker.translateStartCount(text: "toggle-history") == 2
        }
        XCTAssertTrue(didStart)

        tracker.setHistoryEnabled(false)
        viewModel.stopTranslate()
        let didStop = await waitUntil(timeout: 1.0) {
            viewModel.literalState == .stopped && viewModel.rewriteState == .stopped
        }
        XCTAssertTrue(didStop)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(tracker.historyRecord(forInput: "toggle-history"))
    }

    @MainActor
    func testManualStopWritesStoppedHistory() async {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        viewModel.acceptExternalText("first")
        let didStart = await waitUntil(timeout: 1.0) {
            tracker.translateStartCount(text: "first") == 2
        }
        XCTAssertTrue(didStart)

        viewModel.stopTranslate()
        let didWriteStopped = await waitUntil(timeout: 1.0) {
            tracker.historyRecord(forInput: "first")?.status == "stopped"
        }
        XCTAssertTrue(didWriteStopped)
        XCTAssertEqual(viewModel.literalState, .stopped)
        XCTAssertEqual(viewModel.rewriteState, .stopped)
    }

    @MainActor
    func testSingleFailureKeepsSuccessfulOtherPartResult() async {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        viewModel.acceptExternalText("single-failure")
        let didFinish = await waitUntil(timeout: 1.0) {
            tracker.historyRecord(forInput: "single-failure")?.status == "failed"
        }
        XCTAssertTrue(didFinish)
        if case .failed = viewModel.literalState {
            // 直译失败符合预期。
        } else {
            XCTFail("直译分段应失败")
        }
        XCTAssertEqual(viewModel.rewriteState, .done)
        XCTAssertEqual(viewModel.rewriteResult, "新任务片段")
    }

    @MainActor
    func testNotConfiguredPreservesInputAndWritesFailedHistory() async {
        let tracker = EventTracker()
        let viewModel = makeViewModel(eventTracker: tracker)

        let input = "  未配置时保留原文\n"
        viewModel.acceptExternalText(input)
        let didFinish = await waitUntil(timeout: 1.0) {
            tracker.historyRecord(forInput: input)?.status == "failed"
        }
        XCTAssertTrue(didFinish)
        XCTAssertEqual(viewModel.inputText, input)
        XCTAssertEqual(
            viewModel.literalState,
            .failed("请先在设置中填写接口地址、模型名和 API Key")
        )
        XCTAssertEqual(
            viewModel.rewriteState,
            .failed("请先在设置中填写接口地址、模型名和 API Key")
        )
    }

    @MainActor
    private func makeViewModel(eventTracker: EventTracker) -> PanelViewModel {
        PanelViewModel(
            translate: { text, template in
                eventTracker.recordTranslateStart(text: text)
                return AsyncThrowingStream { continuation in
                    let task = Task {
                        if text == "  未配置时保留原文\n" {
                            continuation.finish(throwing: TranslationError.notConfigured)
                        } else if ["partial-first", "single-failure"].contains(text),
                                  template.hasPrefix("literal:") {
                            continuation.finish(throwing: TranslationError.network("单路失败"))
                        } else if ["first", "partial-first", "toggle-history"].contains(text) {
                            continuation.yield("旧任务片段")
                            do {
                                while true {
                                    try await Task.sleep(nanoseconds: 30_000_000)
                                    try Task.checkCancellation()
                                }
                            } catch is CancellationError {
                                continuation.finish(throwing: CancellationError())
                                return
                            } catch {
                                continuation.finish(throwing: error)
                                return
                            }
                        } else {
                            continuation.yield("新任务片段")
                            continuation.finish()
                        }
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            },
            loadConfig: {
                .init(
                    modelName: "unit-test-model",
                    literalTemplate: "literal: {{text}}",
                    rewriteTemplate: "rewrite: {{text}}",
                    historyEnabled: eventTracker.isHistoryEnabled
                )
            },
            appendHistory: { record in
                eventTracker.recordHistory(status: record.status, input: record.input)
            }
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

private final class EventTracker: @unchecked Sendable {
    struct HistoryEvent {
        let order: Int
        let status: String
        let input: String
    }

    private let lock = NSLock()
    private var order: Int = 0
    private var translateOrdersByText: [String: [Int]] = [:]
    private var historyEventsByInput: [String: HistoryEvent] = [:]
    private var historyEnabled = true

    var isHistoryEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return historyEnabled
    }

    func setHistoryEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        historyEnabled = enabled
    }

    func recordTranslateStart(text: String) {
        lock.lock()
        defer { lock.unlock() }
        order += 1
        translateOrdersByText[text, default: []].append(order)
    }

    func recordHistory(status: String, input: String) {
        lock.lock()
        defer { lock.unlock() }
        order += 1
        historyEventsByInput[input] = HistoryEvent(order: order, status: status, input: input)
    }

    func translateCallCount(for char: Character, count: Int) -> Int {
        let text = String(repeating: String(char), count: count)
        lock.lock()
        defer { lock.unlock() }
        return translateOrdersByText[text]?.count ?? 0
    }

    func translateStartCount(text: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return translateOrdersByText[text]?.count ?? 0
    }

    func firstTranslateOrder(text: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return translateOrdersByText[text]?.first
    }

    func historyRecord(forInput input: String) -> HistoryEvent? {
        lock.lock()
        defer { lock.unlock() }
        return historyEventsByInput[input]
    }
}
