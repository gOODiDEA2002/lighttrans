import Foundation
import Darwin
import os

public final class ProcessSafeHistoryStore: @unchecked Sendable {
    public static let shared = ProcessSafeHistoryStore()

    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "history")
    private let fileManager: FileManager
    private let configurationProvider: any TranslationConfigurationProviding
    private let ioQueue = DispatchQueue(label: "com.andy.lighttrans.history.io")
    private let lockTimeoutSeconds: TimeInterval

    public let historyDirURL: URL
    public let lockDirURL: URL
    public let isICloudAvailable: Bool

    public init(
        fileManager: FileManager = .default,
        configurationProvider: any TranslationConfigurationProviding = SharedConfigurationProvider(),
        historyDirURL: URL? = nil,
        lockDirURL: URL? = nil,
        lockTimeoutSeconds: TimeInterval = 5
    ) {
        self.fileManager = fileManager
        self.configurationProvider = configurationProvider
        self.lockTimeoutSeconds = lockTimeoutSeconds

        let iCloudBase = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDir: ObjCBool = false
        let iCloudReady = fileManager.fileExists(atPath: iCloudBase.path, isDirectory: &isDir) && isDir.boolValue

        if let historyDirURL {
            self.historyDirURL = historyDirURL
            self.isICloudAvailable = false
        } else if iCloudReady {
            self.historyDirURL = iCloudBase.appendingPathComponent("LightTrans/history", isDirectory: true)
            self.isICloudAvailable = true
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.historyDirURL = appSupport.appendingPathComponent("LightTrans/history", isDirectory: true)
            self.isICloudAvailable = false
        }

        if let lockDirURL {
            self.lockDirURL = lockDirURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.lockDirURL = appSupport.appendingPathComponent("LightTrans/locks", isDirectory: true)
        }
    }

    private var localFileSuffix: String {
        String(configurationProvider.deviceID().prefix(8))
    }

    private var localV2HistoryFileURL: URL {
        historyDirURL.appendingPathComponent("history-v2-\(localFileSuffix).jsonl")
    }

    private var localLockFileURL: URL {
        lockDirURL.appendingPathComponent("history-v2-\(localFileSuffix).lock")
    }

    public func append(_ record: HistoryRecord) async -> HistoryWriteOutcome {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                continuation.resume(returning: self.appendSync(record))
            }
        }
    }

    public func loadAll() async -> (records: [HistoryRecord], pendingDevices: Int) {
        await withCheckedContinuation { continuation in
            ioQueue.async {
                continuation.resume(returning: self.loadAllSync())
            }
        }
    }

    private func appendSync(_ record: HistoryRecord) -> HistoryWriteOutcome {
        do {
            try ensurePrivateDirectory(at: historyDirURL)
            try ensurePrivateDirectory(at: lockDirURL)

            var data = try JSONEncoder().encode(record)
            data.append(0x0A)

            let lockFD = try openFile(localLockFileURL, flags: O_CREAT | O_RDWR | O_CLOEXEC, mode: 0o600)
            defer {
                _ = flock(lockFD, LOCK_UN)
                _ = close(lockFD)
            }
            guard acquireLock(lockFD: lockFD, timeoutSeconds: lockTimeoutSeconds) else {
                logger.error("历史锁获取超时")
                return .failed
            }

            let historyFD = try openFile(localV2HistoryFileURL, flags: O_CREAT | O_APPEND | O_WRONLY | O_CLOEXEC, mode: 0o600)
            defer {
                _ = close(historyFD)
            }
            try writeAll(fd: historyFD, data: data)
            try syncFile(fd: historyFD)
            return .written
        } catch {
            logger.error("历史写入失败：\(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func loadAllSync() -> (records: [HistoryRecord], pendingDevices: Int) {
        guard let entries = try? fileManager.contentsOfDirectory(at: historyDirURL, includingPropertiesForKeys: nil) else {
            return ([], 0)
        }
        var byID: [String: HistoryRecord] = [:]
        var pending = 0
        let decoder = JSONDecoder()

        for url in entries {
            let name = url.lastPathComponent
            if name.hasSuffix(".icloud") {
                pending += 1
                try? fileManager.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard name.hasPrefix("history-"), name.hasSuffix(".jsonl") else {
                continue
            }
            let content: String?
            if url.lastPathComponent == localV2HistoryFileURL.lastPathComponent {
                content = readLocalV2FileWithSharedLock(url: url)
            } else {
                content = try? String(contentsOf: url, encoding: .utf8)
            }
            guard let content else {
                continue
            }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard
                    let lineData = line.data(using: .utf8),
                    let record = try? decoder.decode(HistoryRecord.self, from: lineData)
                else {
                    logger.error("历史坏行跳过")
                    continue
                }
                byID[record.id] = record
            }
        }

        let sorted = byID.values.sorted {
            (Self.parseTime($0.time) ?? .distantPast) > (Self.parseTime($1.time) ?? .distantPast)
        }
        return (sorted, pending)
    }

    private func readLocalV2FileWithSharedLock(url: URL) -> String? {
        do {
            try ensurePrivateDirectory(at: lockDirURL)
            let lockFD = try openFile(localLockFileURL, flags: O_CREAT | O_RDWR | O_CLOEXEC, mode: 0o600)
            defer {
                _ = flock(lockFD, LOCK_UN)
                _ = close(lockFD)
            }
            guard acquireSharedLock(lockFD: lockFD, timeoutSeconds: lockTimeoutSeconds) else {
                logger.error("历史读取锁获取超时")
                return nil
            }
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.error("历史读取失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func parseTime(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func openFile(_ url: URL, flags: Int32, mode: mode_t) throws -> Int32 {
        let fd = open(url.path, flags, mode)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return fd
    }

    private func acquireLock(lockFD: Int32, timeoutSeconds: TimeInterval) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            if flock(lockFD, LOCK_EX | LOCK_NB) == 0 {
                return true
            }
            if errno == EINTR {
                continue
            }
            if errno == EWOULDBLOCK {
                usleep(20_000)
                continue
            }
            return false
        }
        return false
    }

    private func acquireSharedLock(lockFD: Int32, timeoutSeconds: TimeInterval) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            if flock(lockFD, LOCK_SH | LOCK_NB) == 0 {
                return true
            }
            if errno == EINTR {
                continue
            }
            if errno == EWOULDBLOCK {
                usleep(20_000)
                continue
            }
            return false
        }
        return false
    }

    private func writeAll(fd: Int32, data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            while offset < data.count {
                let pointer = baseAddress.advanced(by: offset)
                let written = write(fd, pointer, data.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written == 0 {
                    throw POSIXError(.EIO)
                }
                if errno == EINTR {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    private func ensurePrivateDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(url.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func syncFile(fd: Int32) throws {
        while fsync(fd) != 0 {
            if errno == EINTR {
                continue
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
