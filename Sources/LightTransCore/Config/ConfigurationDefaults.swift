import Foundation

public enum ConfigurationDefaults {
    public static let userDefaultsSuiteName = "com.andy.lighttrans"
    public static let keyAPIBaseURL = "apiBaseURL"
    public static let keyModelName = "modelName"
    public static let keyLiteralPromptTemplate = "literalPromptTemplate"
    public static let keyPromptTemplate = "promptTemplate"
    public static let keyMaxTokens = "maxTokens"
    public static let keyHistoryEnabled = "historyEnabled"
    public static let keyDeviceID = "deviceID"

    public static let keychainService = "LightTrans"
    public static let keychainAccount = "apiKey"

    public static let defaultAPIBaseURL = "https://api.openai.com/v1"
    public static let defaultModelName = ""
    public static let defaultMaxTokens = 2000
    public static let defaultHistoryEnabled = true

    public static let defaultLiteralPromptTemplate = """
    你是专业翻译。请翻译下面这段文字：如果原文以中文为主，翻译成英文；否则翻译成简体中文。只输出译文本身，不要任何解释或多余内容。

    {{text}}
    """

    public static let defaultRewritePromptTemplate = """
    你是提示词工程专家。请把下面这段文字改写成一段结构清晰、指令明确的英文提示词，可直接交给大模型使用。只输出改写后的提示词本身，不要任何解释。

    {{text}}
    """

    public static let defaultValues: [String: Any] = [
        keyAPIBaseURL: defaultAPIBaseURL,
        keyModelName: defaultModelName,
        keyLiteralPromptTemplate: defaultLiteralPromptTemplate,
        keyPromptTemplate: defaultRewritePromptTemplate,
        keyMaxTokens: defaultMaxTokens,
        keyHistoryEnabled: defaultHistoryEnabled
    ]
}
