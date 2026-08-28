import Foundation
import XCTest

final class CLIExecutableTests: XCTestCase {
    func testHelpAndVersionDoNotRequireInput() throws {
        let help = try runCLI(arguments: ["--help"])
        XCTAssertEqual(help.status, 0)
        XCTAssertTrue(help.stdout.contains("lt [--mode literal|rewrite|both]"))
        XCTAssertEqual(help.stderr, "")

        let version = try runCLI(arguments: ["--version"])
        XCTAssertEqual(version.status, 0)
        XCTAssertEqual(version.stdout, "development\n")
        XCTAssertEqual(version.stderr, "")
    }

    func testVersionResolvesAppInfoWhenLaunchedThroughPATHSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LightTransCLIVersionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let helpers = root.appendingPathComponent("LightTrans.app/Contents/Helpers", isDirectory: true)
        let commands = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)

        let packagedCLI = helpers.appendingPathComponent("lt")
        try FileManager.default.copyItem(at: try cliExecutableURL(), to: packagedCLI)
        let infoURL = root.appendingPathComponent("LightTrans.app/Contents/Info.plist")
        let info: [String: Any] = ["CFBundleShortVersionString": "9.8.7"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)

        let commandLink = commands.appendingPathComponent("lt")
        try FileManager.default.createSymbolicLink(at: commandLink, withDestinationURL: packagedCLI)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["lt", "--version"]
        process.environment = ["PATH": commands.path]
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), "9.8.7\n")
        XCTAssertEqual(String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), "")
    }

    func testUnknownOptionReturnsUsageError() throws {
        let result = try runCLI(arguments: ["--unknown"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("未知参数"))
    }

    func testPipedEmptyInputReturnsUsageErrorWithoutStartingWorkflow() throws {
        let result = try runCLI(arguments: [], standardInput: Data())
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("未提供可翻译文本"))
        XCTAssertEqual(result.stdout, "")
    }

    func testPositionArgumentsConflictWithNonTerminalStandardInput() throws {
        let result = try runCLI(arguments: ["text"], standardInput: Data())
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("位置参数与标准输入不能同时提供"))
    }

    private func runCLI(
        arguments: [String],
        standardInput: Data? = nil
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = try cliExecutableURL()
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if let standardInput {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            try stdin.fileHandleForWriting.write(contentsOf: standardInput)
            try stdin.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
            try process.run()
        }

        process.waitUntilExit()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(decoding: stdoutData, as: UTF8.self),
            String(decoding: stderrData, as: UTF8.self)
        )
    }

    private func cliExecutableURL() throws -> URL {
        let candidate = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("lt")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw NSError(domain: "LightTransCLITests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "找不到 CLI 可执行文件：\(candidate.path)"
            ])
        }
        return candidate
    }
}
