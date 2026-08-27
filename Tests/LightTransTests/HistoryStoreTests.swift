import Foundation
import XCTest
@testable import LightTrans

final class HistoryStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransTests-\(UUID().uuidString)", isDirectory: true)
        store = HistoryStore(historyDirURL: directoryURL) { "12345678-test-device" }
    }

    override func tearDownWithError() throws {
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        store = nil
        directoryURL = nil
        try super.tearDownWithError()
    }

    func testAppendAndLoadRecord() {
        let record = makeRecord(id: "record-1", time: "2026-08-27T10:00:00Z")

        store.append(record)
        let result = store.loadAll()

        XCTAssertEqual(result.records.map(\.id), ["record-1"])
        XCTAssertEqual(result.records.first?.input, "测试原文")
        XCTAssertEqual(result.pendingDevices, 0)
    }

    func testLoadSortsNewestFirstAndDeduplicatesByID() {
        store.append(makeRecord(id: "same-id", time: "2026-08-27T09:00:00Z", literal: "旧值"))
        store.append(makeRecord(id: "newer-id", time: "2026-08-27T11:00:00Z"))
        store.append(makeRecord(id: "same-id", time: "2026-08-27T12:00:00Z", literal: "更新值"))

        let records = store.loadAll().records

        XCTAssertEqual(records.map(\.id), ["same-id", "newer-id"])
        XCTAssertEqual(records.first?.literalOutput, "更新值")
    }

    func testLoadSkipsMalformedLine() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let valid = try JSONEncoder().encode(makeRecord(id: "valid", time: "2026-08-27T10:00:00Z"))
        var content = Data("not-json\n".utf8)
        content.append(valid)
        content.append(Data("\n".utf8))
        try content.write(to: directoryURL.appendingPathComponent("history-external.jsonl"))

        XCTAssertEqual(store.loadAll().records.map(\.id), ["valid"])
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
            output: nil,
            literalOutput: literal,
            rewriteOutput: "测试转写",
            error: nil
        )
    }
}
