import Foundation
import os

// 一条历史记录（详细设计 10.3）。error 仅在 status 为 failed 时出现。
struct HistoryRecord: Codable, Identifiable {
    let id: String
    let time: String      // ISO 8601，含时区偏移
    let device: String
    let model: String
    let status: String    // done / stopped / failed
    let input: String
    let output: String
    let error: String?
}

// 历史记录追加写入与多设备合并读取（详细设计第 10 节，铁律 L-7、L-8）
final class HistoryStore {
    static let shared = HistoryStore()

    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "history")
    private let fileManager = FileManager.default
    let historyDirURL: URL
    // iCloud 云盘目录是否可用（启动时判定一次并缓存）
    let isICloudAvailable: Bool

    private init() {
        let iCloudBase = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: iCloudBase.path, isDirectory: &isDir)
        if exists && isDir.boolValue {
            historyDirURL = iCloudBase.appendingPathComponent("LightTrans/history", isDirectory: true)
            isICloudAvailable = true
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            historyDirURL = appSupport.appendingPathComponent("LightTrans/history", isDirectory: true)
            isICloudAvailable = false
        }
    }

    // 本机历史文件名：history-{deviceID 前 8 位}.jsonl（铁律 L-8，本机只写这一个文件）
    private var localFileURL: URL {
        let suffix = String(ConfigStore.shared.deviceID.prefix(8))
        return historyDirURL.appendingPathComponent("history-\(suffix).jsonl")
    }

    // 追加一条记录；任何失败仅记日志，不抛给调用方（详细设计 10.4）
    func append(_ record: HistoryRecord) {
        do {
            try fileManager.createDirectory(at: historyDirURL, withIntermediateDirectories: true)
            var line = try JSONEncoder().encode(record)   // 紧凑单行，JSON 天然转义换行
            line.append(0x0A)                              // 以换行符结尾
            let url = localFileURL
            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url)
            }
        } catch {
            logger.error("历史写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    // 读入目录下全部设备文件，按 id 去重、按时间倒序返回；统计待下载的占位文件数（详细设计 10.4）
    func loadAll() -> (records: [HistoryRecord], pendingDevices: Int) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: historyDirURL, includingPropertiesForKeys: nil) else {
            return ([], 0)
        }
        var byID: [String: HistoryRecord] = [:]
        var pending = 0
        let decoder = JSONDecoder()
        for url in entries {
            let name = url.lastPathComponent
            // 其他设备记录尚未从云端下载：本地只有 .icloud 占位文件（对应假设 A-5）
            if name.hasSuffix(".icloud") {
                pending += 1
                try? fileManager.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard name.hasPrefix("history-"), name.hasSuffix(".jsonl") else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(HistoryRecord.self, from: data) else {
                    logger.error("历史坏行跳过")
                    continue   // 坏行跳过，不中断
                }
                byID[record.id] = record
            }
        }
        let sorted = byID.values.sorted {
            (Self.parseTime($0.time) ?? .distantPast) > (Self.parseTime($1.time) ?? .distantPast)
        }
        return (sorted, pending)
    }

    private static func parseTime(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }
}
