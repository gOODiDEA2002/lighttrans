import XCTest
@testable import LightTransCore

final class TranslationWorkflowTests: XCTestCase {
    func testLiteralModeOnlyRunsLiteralRoute() async throws {
        let provider = TestConfigurationProvider()
        let store = makeStore(provider: provider)
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { route, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(route == .literal ? "L" : "R")
                    continuation.finish()
                }
            }
        )

        let summary = await workflow.run(request: .init(text: "text", mode: .literal)) { _ in }

        XCTAssertEqual(summary.mode, .literal)
        XCTAssertEqual(summary.status, .done)
        XCTAssertNotNil(summary.literal)
        XCTAssertNil(summary.rewrite)
        XCTAssertEqual(summary.literal?.text, "L")
        XCTAssertEqual(summary.history, .written)

        let stored = await store.loadAll()
        XCTAssertEqual(stored.records.count, 1)
        XCTAssertEqual(stored.records.first?.mode, .literal)
    }

    func testBothModeKeepsSingleRouteFailure() async {
        let provider = TestConfigurationProvider()
        let store = makeStore(provider: provider)
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { route, _, _, _ in
                AsyncThrowingStream { continuation in
                    if route == .literal {
                        continuation.yield("ok")
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: TranslationError.network("网络失败"))
                    }
                }
            }
        )

        let summary = await workflow.run(request: .init(text: "text", mode: .both)) { _ in }
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.literal?.status, .done)
        XCTAssertEqual(summary.literal?.text, "ok")
        XCTAssertEqual(summary.rewrite?.status, .failed)

        let records = (await store.loadAll()).records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.status, "failed")
        XCTAssertEqual(records.first?.literalOutput, "ok")
        XCTAssertEqual(records.first?.rewriteOutput, "")
    }

    func testCancellationStatusPrefersStopped() async {
        let provider = TestConfigurationProvider()
        let store = makeStore(provider: provider)
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { route, _, _, _ in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        if route == .literal {
                            continuation.finish(throwing: TranslationError.badResponse("先失败"))
                        } else {
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 20_000_000)
                            }
                            continuation.finish(throwing: CancellationError())
                        }
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            }
        )

        let task = Task {
            await workflow.run(request: .init(text: "text", mode: .both)) { _ in }
        }
        try? await Task.sleep(nanoseconds: 40_000_000)
        task.cancel()
        let summary = await task.value
        XCTAssertEqual(summary.status, .stopped)

        let records = (await store.loadAll()).records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.status, "stopped")
        XCTAssertNil(records.first?.error)
    }

    func testHistorySwitchReadAtEnd() async {
        let provider = TestConfigurationProvider()
        let store = makeStore(provider: provider)
        let gate = AsyncGate()
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { route, _, _, _ in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        await gate.wait()
                        continuation.yield(route == .literal ? "A" : "B")
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )

        let task = Task {
            await workflow.run(request: .init(text: "text", mode: .both)) { _ in }
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        provider.setHistoryEnabled(false)
        await gate.open()
        let summary = await task.value
        XCTAssertEqual(summary.history, .disabled)
        let records = (await store.loadAll()).records
        XCTAssertEqual(records.count, 0)
    }

    func testConfigurationSnapshotIsLoadedOnceForBothRoutes() async {
        let provider = TestConfigurationProvider()
        let store = makeStore(provider: provider)
        let observations = SnapshotObservations()
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { route, _, snapshot, configuration in
                AsyncThrowingStream { continuation in
                    Task {
                        await observations.record(route: route, snapshot: snapshot, configuration: configuration)
                        continuation.yield(route.rawValue)
                        continuation.finish()
                    }
                }
            }
        )

        let summary = await workflow.run(request: .init(text: "text", mode: .both)) { _ in }

        XCTAssertEqual(summary.status, .done)
        XCTAssertEqual(provider.snapshotLoadCount, 1)
        let captured = await observations.values()
        XCTAssertEqual(captured.count, 2)
        let expectedConfiguration = ModelRequestConfiguration(
            apiBaseURL: "https://example.com/v1",
            modelName: "model",
            apiKey: "key",
            maxTokens: 2000
        )
        XCTAssertTrue(captured.allSatisfy { $0.configuration == expectedConfiguration })
        XCTAssertTrue(captured.allSatisfy { $0.snapshot == provider.currentSnapshot })
    }

    func testConfigurationAccessFailureEmitsStartedAndWritesOneFailedHistory() async {
        let provider = TestConfigurationProvider(snapshotError: .keychainUnavailable)
        let store = makeStore(provider: provider)
        let events = EventRecorder()
        let workflow = TranslationWorkflow(configurationProvider: provider, historyStore: store)

        let summary = await workflow.run(request: .init(text: "原文", mode: .both)) { event in
            await events.append(event)
        }

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.literal?.failure?.code, .configurationUnavailable)
        XCTAssertEqual(summary.rewrite?.failure?.code, .configurationUnavailable)
        let captured = await events.values()
        guard case .started = captured.first else {
            return XCTFail("started 必须是第一个事件")
        }
        guard case .finished(let finalSummary) = captured.last else {
            return XCTFail("finished 必须是最后一个事件")
        }
        XCTAssertEqual(finalSummary, summary)
        XCTAssertEqual(captured.filter { if case .routeFinished = $0 { return true }; return false }.count, 2)
        let records = (await store.loadAll()).records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.status, "failed")
    }

    func testCancellationDuringStartedOverridesConfigurationFailure() async {
        let provider = TestConfigurationProvider(snapshotError: .keychainUnavailable)
        let store = makeStore(provider: provider)
        let started = AsyncGate()
        let releaseStarted = AsyncGate()
        let workflow = TranslationWorkflow(configurationProvider: provider, historyStore: store)
        let task = Task {
            await workflow.run(request: .init(text: "原文", mode: .both)) { event in
                if case .started = event {
                    await started.open()
                    await releaseStarted.wait()
                }
            }
        }

        await started.wait()
        task.cancel()
        await releaseStarted.open()
        let summary = await task.value

        XCTAssertEqual(summary.status, .stopped)
        let records = (await store.loadAll()).records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.status, "stopped")
        XCTAssertNil(records.first?.error)
    }

    func testNotConfiguredPreservesInputAndDoesNotStartNetwork() async {
        let provider = TestConfigurationProvider(snapshot: .init(
            apiBaseURL: "https://example.com/v1",
            modelName: "model",
            apiKey: nil,
            maxTokens: 2000,
            literalTemplate: "literal: {{text}}",
            rewriteTemplate: "rewrite: {{text}}"
        ))
        let store = makeStore(provider: provider)
        let calls = CallCounter()
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { _, _, _, _ in
                calls.increment()
                return AsyncThrowingStream { $0.finish() }
            }
        )
        let input = "  未配置时保留原文\n"

        let summary = await workflow.run(request: .init(text: input, mode: .both)) { _ in }

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.literal?.failure?.code, .notConfigured)
        XCTAssertEqual(summary.rewrite?.failure?.code, .notConfigured)
        XCTAssertEqual(calls.value, 0)
        let records = (await store.loadAll()).records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.input, input)
    }

    func testRewriteModeLeavesLiteralHistoryFieldAbsent() async {
        let provider = TestConfigurationProvider()
        let store = makeStore(provider: provider)
        let workflow = TranslationWorkflow(
            configurationProvider: provider,
            historyStore: store,
            translateStream: { _, _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield("rewrite-only")
                    continuation.finish()
                }
            }
        )

        let summary = await workflow.run(request: .init(text: "text", mode: .rewrite)) { _ in }

        XCTAssertNil(summary.literal)
        XCTAssertEqual(summary.rewrite?.text, "rewrite-only")
        let record = (await store.loadAll()).records.first
        XCTAssertEqual(record?.mode, .rewrite)
        XCTAssertNil(record?.literalOutput)
        XCTAssertEqual(record?.rewriteOutput, "rewrite-only")
    }

    private func makeStore(provider: TestConfigurationProvider) -> ProcessSafeHistoryStore {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-tests-\(UUID().uuidString)", isDirectory: true)
        let lock = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-locks-\(UUID().uuidString)", isDirectory: true)
        return ProcessSafeHistoryStore(
            configurationProvider: provider,
            historyDirURL: temp,
            lockDirURL: lock
        )
    }
}

private final class TestConfigurationProvider: @unchecked Sendable, TranslationConfigurationProviding {
    private let lock = NSLock()
    private var historyEnabled = true
    private var loadCount = 0
    private let snapshot: TranslationConfigurationSnapshot
    private let snapshotError: ConfigurationProviderError?

    init(
        snapshot: TranslationConfigurationSnapshot = .init(
            apiBaseURL: "https://example.com/v1",
            modelName: "model",
            apiKey: "key",
            maxTokens: 2000,
            literalTemplate: "literal: {{text}}",
            rewriteTemplate: "rewrite: {{text}}"
        ),
        snapshotError: ConfigurationProviderError? = nil
    ) {
        self.snapshot = snapshot
        self.snapshotError = snapshotError
    }

    var snapshotLoadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCount
    }

    var currentSnapshot: TranslationConfigurationSnapshot { snapshot }

    func setHistoryEnabled(_ value: Bool) {
        lock.lock()
        historyEnabled = value
        lock.unlock()
    }

    func loadRequestSnapshot() throws -> TranslationConfigurationSnapshot {
        lock.lock()
        loadCount += 1
        lock.unlock()
        if let snapshotError {
            throw snapshotError
        }
        return snapshot
    }

    func isHistoryEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return historyEnabled
    }

    func deviceID() -> String {
        "12345678-test-device"
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private actor SnapshotObservations {
    struct Value {
        let route: TranslationRoute
        let snapshot: TranslationConfigurationSnapshot
        let configuration: ModelRequestConfiguration
    }

    private var captured: [Value] = []

    func record(
        route: TranslationRoute,
        snapshot: TranslationConfigurationSnapshot,
        configuration: ModelRequestConfiguration
    ) {
        captured.append(.init(route: route, snapshot: snapshot, configuration: configuration))
    }

    func values() -> [Value] { captured }
}

private actor EventRecorder {
    private var events: [TranslationEvent] = []

    func append(_ event: TranslationEvent) {
        events.append(event)
    }

    func values() -> [TranslationEvent] { events }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
