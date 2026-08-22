import Foundation

// 配置读写的唯一入口（详细设计第 2 节）
// 非敏感配置存 UserDefaults；API Key 经 KeychainHelper 即取即用，不作属性缓存
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    // UserDefaults 键名
    private enum Key {
        static let apiBaseURL = "apiBaseURL"
        static let modelName = "modelName"
        static let literalPromptTemplate = "literalPromptTemplate"   // 直译模板（增量 v1.1）
        static let promptTemplate = "promptTemplate"                 // 转写模板（沿用原键名）
        static let maxTokens = "maxTokens"
        static let historyEnabled = "historyEnabled"
        static let deviceID = "deviceID"
    }

    // API Key 的钥匙串坐标
    static let keychainService = "LightTrans"
    static let keychainAccount = "apiKey"

    // 默认接口地址
    static let defaultAPIBaseURL = "https://api.openai.com/v1"

    // 默认直译提示词模板（详细设计 11.1.1）
    static let defaultLiteralPromptTemplate = """
    你是专业翻译。请翻译下面这段文字：如果原文以中文为主，翻译成英文；否则翻译成简体中文。只输出译文本身，不要任何解释或多余内容。

    {{text}}
    """

    // 默认转写提示词模板（详细设计 11.1.2，新装机器初值；已自定义的用户保留原值）
    static let defaultRewritePromptTemplate = """
    你是提示词工程专家。请把下面这段文字改写成一段结构清晰、指令明确的英文提示词，可直接交给大模型使用。只输出改写后的提示词本身，不要任何解释。

    {{text}}
    """

    private let defaults: UserDefaults

    // 各配置项：didSet 即改即写回 UserDefaults
    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: Key.apiBaseURL) } }
    @Published var modelName: String { didSet { defaults.set(modelName, forKey: Key.modelName) } }
    // 直译模板（增量 v1.1）
    @Published var literalPromptTemplate: String { didSet { defaults.set(literalPromptTemplate, forKey: Key.literalPromptTemplate) } }
    // 转写模板（沿用原键名 promptTemplate）
    @Published var promptTemplate: String { didSet { defaults.set(promptTemplate, forKey: Key.promptTemplate) } }
    @Published var maxTokens: Int { didSet { defaults.set(maxTokens, forKey: Key.maxTokens) } }
    @Published var historyEnabled: Bool { didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) } }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 注册默认值：从未写入过时读到这些值，且不落盘，用户修改后才持久化
        defaults.register(defaults: [
            Key.apiBaseURL: Self.defaultAPIBaseURL,
            Key.modelName: "",
            Key.literalPromptTemplate: Self.defaultLiteralPromptTemplate,
            Key.promptTemplate: Self.defaultRewritePromptTemplate,
            Key.maxTokens: 2000,
            Key.historyEnabled: true
        ])
        // 属性初始化不触发 didSet，不会把默认值写盘
        self.apiBaseURL = defaults.string(forKey: Key.apiBaseURL) ?? Self.defaultAPIBaseURL
        self.modelName = defaults.string(forKey: Key.modelName) ?? ""
        self.literalPromptTemplate = defaults.string(forKey: Key.literalPromptTemplate) ?? Self.defaultLiteralPromptTemplate
        self.promptTemplate = defaults.string(forKey: Key.promptTemplate) ?? Self.defaultRewritePromptTemplate
        self.maxTokens = defaults.integer(forKey: Key.maxTokens)
        self.historyEnabled = defaults.bool(forKey: Key.historyEnabled)
    }

    // 设备标识：首次访问生成 UUID 并持久化，此后不变（详细设计第 2 节表、10.2）
    var deviceID: String {
        if let existing = defaults.string(forKey: Key.deviceID) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Key.deviceID)
        return generated
    }

    // API Key 即取即用，不缓存
    func loadAPIKey() -> String? {
        KeychainHelper.read(service: Self.keychainService, account: Self.keychainAccount)
    }

    func saveAPIKey(_ key: String) throws {
        try KeychainHelper.save(key, service: Self.keychainService, account: Self.keychainAccount)
    }

    func deleteAPIKey() {
        KeychainHelper.delete(service: Self.keychainService, account: Self.keychainAccount)
    }

    #if DEBUG
    // UI 截图验收专用：隔离到临时 defaults，避免读写真实持久化
    static func uiAcceptanceMock() -> ConfigStore {
        let suiteName = "LightTrans.UIAcceptance.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return ConfigStore(defaults: .standard)
        }
        defaults.set("https://api.openai.com/v1", forKey: "apiBaseURL")
        defaults.set("deepseek-chat", forKey: "modelName")
        defaults.set(2000, forKey: "maxTokens")
        defaults.set(true, forKey: "historyEnabled")
        defaults.set("", forKey: "literalPromptTemplate")
        defaults.set("", forKey: "promptTemplate")
        return ConfigStore(defaults: defaults)
    }
    #endif
}
