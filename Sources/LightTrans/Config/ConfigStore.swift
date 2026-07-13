import Foundation

// 配置读写的唯一入口（详细设计第 2 节）
// 非敏感配置存 UserDefaults；API Key 经 KeychainHelper 即取即用，不作属性缓存
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    // UserDefaults 键名
    private enum Key {
        static let apiBaseURL = "apiBaseURL"
        static let modelName = "modelName"
        static let promptTemplate = "promptTemplate"
        static let maxTokens = "maxTokens"
        static let historyEnabled = "historyEnabled"
        static let deviceID = "deviceID"
    }

    // API Key 的钥匙串坐标
    static let keychainService = "LightTrans"
    static let keychainAccount = "apiKey"

    // 默认接口地址
    static let defaultAPIBaseURL = "https://api.openai.com/v1"

    // 默认提示词模板（详细设计 2.1）
    static let defaultPromptTemplate = """
    你是专业翻译。请翻译下面这段文字：如果原文以中文为主，翻译成英文；否则翻译成简体中文。只输出译文本身，不要任何解释或多余内容。

    {{text}}
    """

    private let defaults: UserDefaults

    // 各配置项：didSet 即改即写回 UserDefaults
    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: Key.apiBaseURL) } }
    @Published var modelName: String { didSet { defaults.set(modelName, forKey: Key.modelName) } }
    @Published var promptTemplate: String { didSet { defaults.set(promptTemplate, forKey: Key.promptTemplate) } }
    @Published var maxTokens: Int { didSet { defaults.set(maxTokens, forKey: Key.maxTokens) } }
    @Published var historyEnabled: Bool { didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) } }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 注册默认值：从未写入过时读到这些值，且不落盘，用户修改后才持久化
        defaults.register(defaults: [
            Key.apiBaseURL: Self.defaultAPIBaseURL,
            Key.modelName: "",
            Key.promptTemplate: Self.defaultPromptTemplate,
            Key.maxTokens: 2000,
            Key.historyEnabled: true
        ])
        // 属性初始化不触发 didSet，不会把默认值写盘
        self.apiBaseURL = defaults.string(forKey: Key.apiBaseURL) ?? Self.defaultAPIBaseURL
        self.modelName = defaults.string(forKey: Key.modelName) ?? ""
        self.promptTemplate = defaults.string(forKey: Key.promptTemplate) ?? Self.defaultPromptTemplate
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
}
