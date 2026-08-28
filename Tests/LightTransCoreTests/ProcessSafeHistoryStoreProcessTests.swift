import Darwin
import Foundation
import XCTest
@testable import LightTransCore

final class ProcessSafeHistoryStoreProcessTests: XCTestCase {
    private let deviceID = "12345678-process-test"
    private var historyDirectory: URL!
    private var lockDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransProcessHistory-\(UUID().uuidString)", isDirectory: true)
        lockDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransProcessLocks-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let historyDirectory {
            try? FileManager.default.removeItem(at: historyDirectory)
        }
        if let lockDirectory {
            try? FileManager.default.removeItem(at: lockDirectory)
        }
        try super.tearDownWithError()
    }

    func testMultipleProcessesAppendWithoutLostOrMalformedLines() async throws {
        let processCount = 50
        let processes = try (0..<processCount).map { index in
            try launchHelper([
                "append",
                historyDirectory.path,
                lockDirectory.path,
                deviceID,
                "process-\(index)",
                String(format: "2026-08-28T10:00:%02dZ", index)
            ])
        }

        for process in processes {
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }

        let store = makeStore()
        let loaded = await store.loadAll()
        XCTAssertEqual(Set(loaded.records.map(\.id)).count, processCount)

        let historyFile = historyDirectory.appendingPathComponent("history-v2-12345678.jsonl")
        let lines = try String(contentsOf: historyFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, processCount)
        for line in lines {
            XCTAssertNoThrow(try JSONDecoder().decode(HistoryRecord.self, from: Data(line.utf8)))
        }
    }

    func testLockTimeoutFailsWithoutUnlockedFallback() async throws {
        let holder = try startLockHolder()
        defer {
            if holder.isRunning {
                kill(holder.processIdentifier, SIGKILL)
                holder.waitUntilExit()
            }
        }

        let store = ProcessSafeHistoryStore(
            configurationProvider: FixedTestConfigurationProvider(deviceID: deviceID),
            historyDirURL: historyDirectory,
            lockDirURL: lockDirectory,
            lockTimeoutSeconds: 0.1
        )
        let result = await store.append(makeRecord(id: "must-not-write"))
        XCTAssertEqual(result, .failed)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: historyDirectory.appendingPathComponent("history-v2-12345678.jsonl").path
        ))
    }

    func testKernelReleasesLockAfterSIGINTAndSIGKILL() async throws {
        for signalValue in [SIGINT, SIGKILL] {
            let holder = try startLockHolder()
            XCTAssertEqual(kill(holder.processIdentifier, signalValue), 0)
            holder.waitUntilExit()

            let process = try launchHelper([
                "append",
                historyDirectory.path,
                lockDirectory.path,
                deviceID,
                "after-signal-\(signalValue)",
                "2026-08-28T10:01:00Z"
            ])
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }

        let loaded = await makeStore().loadAll()
        XCTAssertEqual(loaded.records.count, 2)
    }

    func testCreatedDirectoriesAndFilesUsePrivatePermissions() async throws {
        let result = await makeStore().append(makeRecord(id: "permissions"))
        XCTAssertEqual(result, .written)

        XCTAssertEqual(try permissions(of: historyDirectory), 0o700)
        XCTAssertEqual(try permissions(of: lockDirectory), 0o700)
        XCTAssertEqual(
            try permissions(of: historyDirectory.appendingPathComponent("history-v2-12345678.jsonl")),
            0o600
        )
        XCTAssertEqual(
            try permissions(of: lockDirectory.appendingPathComponent("history-v2-12345678.lock")),
            0o600
        )
    }

    func testConcurrentProcessesShareOneGeneratedDeviceID() throws {
        let suiteName = "com.andy.lighttrans.process-test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let deviceIDLock = lockDirectory.appendingPathComponent("device-id.lock")
        let processes: [(Process, Pipe)] = try (0..<20).map { _ in
            let pipe = Pipe()
            let process = Process()
            process.executableURL = try helperExecutableURL()
            process.arguments = ["device-id", suiteName, deviceIDLock.path]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            return (process, pipe)
        }

        var identifiers: [String] = []
        for (process, pipe) in processes {
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            identifiers.append(String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        XCTAssertEqual(Set(identifiers).count, 1)
        XCTAssertFalse(identifiers.first?.isEmpty ?? true)
    }

    private func startLockHolder() throws -> Process {
        let readyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransLockReady-\(UUID().uuidString)")
        let lockFile = lockDirectory.appendingPathComponent("history-v2-12345678.lock")
        let process = try launchHelper(["hold-lock", lockFile.path, readyFile.path])
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: readyFile.path), Date() < deadline {
            usleep(10_000)
        }
        try? FileManager.default.removeItem(at: readyFile)
        guard FileManager.default.fileExists(atPath: lockFile.path), process.isRunning else {
            process.waitUntilExit()
            throw NSError(domain: "LightTransProcessTest", code: 1)
        }
        return process
    }

    private func launchHelper(_ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = try helperExecutableURL()
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func helperExecutableURL() throws -> URL {
        let candidate = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("LightTransHistoryTestHelper")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw NSError(domain: "LightTransProcessTest", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "找不到历史测试辅助进程：\(candidate.path)"
            ])
        }
        return candidate
    }

    private func makeStore() -> ProcessSafeHistoryStore {
        ProcessSafeHistoryStore(
            configurationProvider: FixedTestConfigurationProvider(deviceID: deviceID),
            historyDirURL: historyDirectory,
            lockDirURL: lockDirectory
        )
    }

    private func makeRecord(id: String) -> HistoryRecord {
        HistoryRecord(
            id: id,
            time: "2026-08-28T10:00:00Z",
            device: "测试设备",
            model: "test-model",
            status: "done",
            input: "测试原文",
            mode: .literal,
            output: nil,
            literalOutput: "测试结果",
            rewriteOutput: nil,
            error: nil
        )
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private struct FixedTestConfigurationProvider: TranslationConfigurationProviding {
    let deviceIDValue: String

    init(deviceID: String) {
        self.deviceIDValue = deviceID
    }

    func loadRequestSnapshot() throws -> TranslationConfigurationSnapshot {
        throw ConfigurationProviderError.userDefaultsUnavailable
    }

    func isHistoryEnabled() -> Bool { true }

    func deviceID() -> String { deviceIDValue }
}
