import Foundation
import XCTest
import LightTransCore

final class HistoryStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var lockDirectoryURL: URL!
    private var store: ProcessSafeHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransTests-\(UUID().uuidString)", isDirectory: true)
        lockDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransLocks-\(UUID().uuidString)", isDirectory: true)
        store = ProcessSafeHistoryStore(
            configurationProvider: TestConfigurationProvider(),
            historyDirURL: directoryURL,
            lockDirURL: lockDirectoryURL
        )
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        if let lockDirectoryURL {
            try? FileManager.default.removeItem(at: lockDirectoryURL)
        }
        store = nil
        directoryURL = nil
        lockDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testAppendAndLoadRecord() async {
        let record = makeRecord(id: "record-1", time: "2026-08-27T10:00:00Z")

        let appendResult = await store.append(record)
        let result = await store.loadAll()

        XCTAssertEqual(appendResult, .written)
        XCTAssertEqual(result.records.map(\.id), ["record-1"])
        XCTAssertEqual(result.records.first?.input, "测试原文")
        XCTAssertEqual(result.pendingDevices, 0)
    }

    func testLoadSortsNewestFirstAndDeduplicatesByID() async {
        _ = await store.append(makeRecord(id: "same-id", time: "2026-08-27T09:00:00Z", literal: "旧值"))
        _ = await store.append(makeRecord(id: "newer-id", time: "2026-08-27T11:00:00Z"))
        _ = await store.append(makeRecord(id: "same-id", time: "2026-08-27T12:00:00Z", literal: "更新值"))

        let records = (await store.loadAll()).records

        XCTAssertEqual(records.map(\.id), ["same-id", "newer-id"])
        XCTAssertEqual(records.first?.literalOutput, "更新值")
    }

    func testLoadMergesLegacyAndV2FilesByIDAndTime() async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let legacyURL = directoryURL.appendingPathComponent("history-legacy001.jsonl")
        let legacyRecords = [
            makeRecord(id: "shared", time: "2026-08-27T09:00:00Z", literal: "legacy"),
            makeRecord(id: "legacy-only", time: "2026-08-27T10:00:00Z")
        ]
        var legacyData = Data()
        for record in legacyRecords {
            legacyData.append(try JSONEncoder().encode(record))
            legacyData.append(0x0A)
        }
        try legacyData.write(to: legacyURL)

        _ = await store.append(makeRecord(id: "shared", time: "2026-08-27T12:00:00Z", literal: "v2"))
        _ = await store.append(makeRecord(id: "v2-only", time: "2026-08-27T11:00:00Z"))

        let records = (await store.loadAll()).records
        XCTAssertEqual(records.map(\.id), ["shared", "v2-only", "legacy-only"])
        XCTAssertEqual(records.first?.literalOutput, "v2")
    }

    func testLoadSkipsMalformedLine() async throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let valid = try JSONEncoder().encode(makeRecord(id: "valid", time: "2026-08-27T10:00:00Z"))
        var content = Data("not-json\n".utf8)
        content.append(valid)
        content.append(Data("\n".utf8))
        try content.write(to: directoryURL.appendingPathComponent("history-external.jsonl"))

        let result = await store.loadAll()
        XCTAssertEqual(result.records.map(\.id), ["valid"])
    }

    func testConcurrentAppendsKeepAllRecords() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let record = self.makeRecord(
                        id: "id-\(index)",
                        time: "2026-08-27T10:00:\(String(format: "%02d", index % 60))Z",
                        literal: "literal-\(index)"
                    )
                    _ = await self.store.append(record)
                }
            }
        }

        let loaded = await store.loadAll()
        let ids = Set(loaded.records.map(\.id))
        XCTAssertEqual(ids.count, 50)
    }

    func testEffectiveModeSupportsLegacyAndAllNewModes() {
        let legacy = HistoryRecord(
            id: "legacy",
            time: "2026-08-27T10:00:00Z",
            device: "测试设备",
            model: "test-model",
            status: "done",
            input: "测试原文",
            mode: nil,
            output: "旧译文",
            literalOutput: nil,
            rewriteOutput: nil,
            error: nil
        )
        let literal = makeRecord(id: "literal", time: "2026-08-27T10:00:01Z", literal: "")
        let rewrite = HistoryRecord(
            id: "rewrite",
            time: "2026-08-27T10:00:02Z",
            device: "测试设备",
            model: "test-model",
            status: "done",
            input: "测试原文",
            mode: nil,
            output: nil,
            literalOutput: nil,
            rewriteOutput: "",
            error: nil
        )
        let both = makeRecord(id: "both", time: "2026-08-27T10:00:03Z")

        XCTAssertEqual(legacy.effectiveMode, .legacy)
        XCTAssertEqual(literal.effectiveMode, .both)
        XCTAssertEqual(rewrite.effectiveMode, .rewrite)
        XCTAssertEqual(both.effectiveMode, .both)

        let explicitLiteral = HistoryRecord(
            id: "explicit-literal",
            time: "2026-08-27T10:00:04Z",
            device: "测试设备",
            model: "test-model",
            status: "done",
            input: "测试原文",
            mode: .literal,
            output: nil,
            literalOutput: "",
            rewriteOutput: nil,
            error: nil
        )
        XCTAssertEqual(explicitLiteral.effectiveMode, .literal)
    }

    private func makeRecord(
        id: String,
        time: String,
        literal: String = "测试译文"
    ) -> HistoryRecord {
        HistoryRecord(
            id: id,
            time: time,
            device: "测试设备",
            model: "test-model",
            status: "done",
            input: "测试原文",
            mode: .both,
            output: nil,
            literalOutput: literal,
            rewriteOutput: "测试转写",
            error: nil
        )
    }
}

private struct TestConfigurationProvider: TranslationConfigurationProviding {
    func loadRequestSnapshot() throws -> TranslationConfigurationSnapshot {
        TranslationConfigurationSnapshot(
            apiBaseURL: "https://example.com/v1",
            modelName: "model",
            apiKey: "test-key",
            maxTokens: 2000,
            literalTemplate: "{{text}}",
            rewriteTemplate: "{{text}}"
        )
    }

    func isHistoryEnabled() -> Bool { true }

    func deviceID() -> String { "12345678-test-device" }
}
