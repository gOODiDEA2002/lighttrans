import Darwin
import Foundation
import LightTransCore

private struct FixedConfigurationProvider: TranslationConfigurationProviding {
    let deviceIDValue: String

    func loadRequestSnapshot() throws -> TranslationConfigurationSnapshot {
        throw ConfigurationProviderError.userDefaultsUnavailable
    }

    func isHistoryEnabled() -> Bool { true }

    func deviceID() -> String { deviceIDValue }
}

@main
private enum LightTransHistoryTestHelper {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            exit(2)
        }

        switch command {
        case "append":
            guard arguments.count == 6 else { exit(2) }
            let historyDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let lockDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let deviceID = arguments[3]
            let recordID = arguments[4]
            let time = arguments[5]
            let provider = FixedConfigurationProvider(deviceIDValue: deviceID)
            let store = ProcessSafeHistoryStore(
                configurationProvider: provider,
                historyDirURL: historyDirectory,
                lockDirURL: lockDirectory
            )
            let record = HistoryRecord(
                id: recordID,
                time: time,
                device: "测试辅助进程",
                model: "test-model",
                status: "done",
                input: "input-\(recordID)",
                mode: .literal,
                output: nil,
                literalOutput: "output-\(recordID)",
                rewriteOutput: nil,
                error: nil
            )
            exit(await store.append(record) == .written ? 0 : 1)

        case "hold-lock":
            guard arguments.count == 3 else { exit(2) }
            let lockPath = arguments[1]
            let readyPath = arguments[2]
            let lockDirectory = URL(fileURLWithPath: lockPath).deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(
                    at: lockDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                exit(1)
            }
            let fd = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0, flock(fd, LOCK_EX) == 0 else { exit(1) }
            guard FileManager.default.createFile(atPath: readyPath, contents: Data()) else { exit(1) }
            while true {
                pause()
            }

        case "device-id":
            guard arguments.count == 3,
                  let defaults = UserDefaults(suiteName: arguments[1]) else {
                exit(2)
            }
            let provider = SharedConfigurationProvider(
                defaults: defaults,
                suiteDefaults: defaults,
                deviceIDLockURL: URL(fileURLWithPath: arguments[2]),
                keychainReader: { _, _ in nil }
            )
            print(provider.deviceID())
            exit(0)

        default:
            exit(2)
        }
    }
}
