import Foundation
import Darwin
import os

public struct TranslationConfigurationSnapshot: Sendable, Equatable {
    public let apiBaseURL: String
    public let modelName: String
    public let apiKey: String?
    public let maxTokens: Int
    public let literalTemplate: String
    public let rewriteTemplate: String

    public init(
        apiBaseURL: String,
        modelName: String,
        apiKey: String?,
        maxTokens: Int,
        literalTemplate: String,
        rewriteTemplate: String
    ) {
        self.apiBaseURL = apiBaseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.maxTokens = maxTokens
        self.literalTemplate = literalTemplate
        self.rewriteTemplate = rewriteTemplate
    }
}

public protocol TranslationConfigurationProviding: Sendable {
    func loadRequestSnapshot() throws -> TranslationConfigurationSnapshot
    func isHistoryEnabled() -> Bool
    func deviceID() -> String
}

public enum ConfigurationProviderError: Error, Sendable, Equatable {
    case userDefaultsUnavailable
    case keychainUnavailable
}

public final class SharedConfigurationProvider: @unchecked Sendable, TranslationConfigurationProviding {
    private static let inProcessDeviceIDLock = NSLock()

    private let defaults: UserDefaults
    private let suiteDefaults: UserDefaults?
    private let keychainReader: @Sendable (String, String) throws -> String?
    private let deviceIDLockURL: URL
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "configuration")

    public init(
        defaults: UserDefaults = .standard,
        suiteDefaults: UserDefaults? = UserDefaults(suiteName: ConfigurationDefaults.userDefaultsSuiteName),
        deviceIDLockURL: URL? = nil,
        keychainReader: @escaping @Sendable (String, String) throws -> String? = { service, account in
            try KeychainHelper.read(service: service, account: account)
        }
    ) {
        self.defaults = defaults
        self.suiteDefaults = suiteDefaults
        self.keychainReader = keychainReader
        if let deviceIDLockURL {
            self.deviceIDLockURL = deviceIDLockURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.deviceIDLockURL = appSupport
                .appendingPathComponent("LightTrans/locks", isDirectory: true)
                .appendingPathComponent("device-id.lock")
        }
        self.defaults.register(defaults: ConfigurationDefaults.defaultValues)
        self.suiteDefaults?.register(defaults: ConfigurationDefaults.defaultValues)
    }

    private var readDefaults: UserDefaults {
        suiteDefaults ?? defaults
    }

    public func loadRequestSnapshot() throws -> TranslationConfigurationSnapshot {
        let ud = readDefaults
        let apiKey: String?
        do {
            apiKey = try keychainReader(ConfigurationDefaults.keychainService, ConfigurationDefaults.keychainAccount)
        } catch {
            throw ConfigurationProviderError.keychainUnavailable
        }

        return TranslationConfigurationSnapshot(
            apiBaseURL: ud.string(forKey: ConfigurationDefaults.keyAPIBaseURL) ?? ConfigurationDefaults.defaultAPIBaseURL,
            modelName: ud.string(forKey: ConfigurationDefaults.keyModelName) ?? ConfigurationDefaults.defaultModelName,
            apiKey: apiKey,
            maxTokens: ud.object(forKey: ConfigurationDefaults.keyMaxTokens) as? Int ?? ConfigurationDefaults.defaultMaxTokens,
            literalTemplate: ud.string(forKey: ConfigurationDefaults.keyLiteralPromptTemplate) ?? ConfigurationDefaults.defaultLiteralPromptTemplate,
            rewriteTemplate: ud.string(forKey: ConfigurationDefaults.keyPromptTemplate) ?? ConfigurationDefaults.defaultRewritePromptTemplate
        )
    }

    public func isHistoryEnabled() -> Bool {
        readDefaults.object(forKey: ConfigurationDefaults.keyHistoryEnabled) as? Bool ?? ConfigurationDefaults.defaultHistoryEnabled
    }

    public func deviceID() -> String {
        let ud = readDefaults
        if let existing = ud.string(forKey: ConfigurationDefaults.keyDeviceID) {
            return existing
        }

        Self.inProcessDeviceIDLock.lock()
        defer { Self.inProcessDeviceIDLock.unlock() }

        do {
            let lockDirectory = deviceIDLockURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: lockDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard chmod(lockDirectory.path, 0o700) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            let fd = open(deviceIDLockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer {
                _ = flock(fd, LOCK_UN)
                _ = close(fd)
            }
            guard acquireDeviceIDLock(fd: fd) else {
                throw POSIXError(.ETIMEDOUT)
            }

            _ = ud.synchronize()
            if let existing = ud.string(forKey: ConfigurationDefaults.keyDeviceID) {
                return existing
            }
            let generated = UUID().uuidString
            ud.set(generated, forKey: ConfigurationDefaults.keyDeviceID)
            _ = ud.synchronize()
            return generated
        } catch {
            logger.error("设备标识锁不可用：\(error.localizedDescription, privacy: .public)")
            if let existing = ud.string(forKey: ConfigurationDefaults.keyDeviceID) {
                return existing
            }
            let generated = UUID().uuidString
            ud.set(generated, forKey: ConfigurationDefaults.keyDeviceID)
            return generated
        }
    }

    private func acquireDeviceIDLock(fd: Int32) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
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
}
