import Foundation

public enum TranslationErrorCode: String, Codable, Sendable, Equatable {
    case notConfigured
    case configurationUnavailable
    case invalidKey
    case rateLimited
    case insufficientQuota
    case badURL
    case network
    case badResponse
}

public enum TranslationError: Error, Equatable, Sendable {
    case notConfigured
    case configurationUnavailable
    case invalidKey
    case rateLimited
    case insufficientQuota
    case badURL
    case network(String)
    case badResponse(String)

    public var code: TranslationErrorCode {
        switch self {
        case .notConfigured:
            return .notConfigured
        case .configurationUnavailable:
            return .configurationUnavailable
        case .invalidKey:
            return .invalidKey
        case .rateLimited:
            return .rateLimited
        case .insufficientQuota:
            return .insufficientQuota
        case .badURL:
            return .badURL
        case .network:
            return .network
        case .badResponse:
            return .badResponse
        }
    }

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "请先在设置中填写接口地址、模型名和 API Key"
        case .configurationUnavailable:
            return "无法读取本机配置或钥匙串，请检查系统权限后重试"
        case .invalidKey:
            return "API Key 无效，请检查设置"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .insufficientQuota:
            return "账户余额不足或额度已用完"
        case .badURL:
            return "接口地址不正确，请检查设置"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .badResponse(let summary):
            return "接口返回异常：\(String(summary.prefix(100)))"
        }
    }

    public var failure: TranslationFailure {
        TranslationFailure(code: code, message: userMessage)
    }
}
