import SwiftUI
import KeyboardShortcuts

// 设置窗口（详细设计第 5 节）。UserDefaults 项即改即存；仅 API Key 在失焦/关闭时写钥匙串。
struct SettingsView: View {
    @ObservedObject private var config = ConfigStore.shared
    @State private var apiKey = ""
    @FocusState private var apiKeyFocused: Bool
    @State private var maxTokensText = ""
    @FocusState private var maxTokensFocused: Bool

    private var templateMissingPlaceholder: Bool {
        !config.promptTemplate.contains("{{text}}")
    }

    var body: some View {
        Form {
            Section("接口") {
                TextField("接口地址", text: $config.apiBaseURL)
                TextField("模型名", text: $config.modelName)
                SecureField("API Key", text: $apiKey)
                    .focused($apiKeyFocused)
                    .onChange(of: apiKeyFocused) { _, focused in
                        if !focused { saveAPIKey() }   // 失焦写回钥匙串
                    }
                TextField("最大输出 token（100–8000）", text: $maxTokensText)
                    .focused($maxTokensFocused)
                    .onChange(of: maxTokensFocused) { _, focused in
                        if !focused { commitMaxTokens() }
                    }
                    .onSubmit { commitMaxTokens() }
            }

            Section("提示词模板") {
                TextEditor(text: $config.promptTemplate)
                    .font(.system(size: 13))
                    .frame(height: 140)
                Text("用 {{text}} 表示待翻译的原文")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if templateMissingPlaceholder {
                    Text("模板未包含 {{text}}，翻译时将把原文追加到模板末尾")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("通用") {
                KeyboardShortcuts.Recorder("呼出翻译面板：", name: .togglePanel)
                // 开机自启开关由 T9 加入本组
            }

            Section("历史记录") {
                Toggle("记录翻译历史", isOn: $config.historyEnabled)
                Text(HistoryStore.shared.isICloudAvailable
                     ? "存储位置：iCloud 云盘（可多设备同步）"
                     : "存储位置：本机（未检测到 iCloud 云盘）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            apiKey = config.loadAPIKey() ?? ""
            maxTokensText = String(config.maxTokens)
        }
        .onDisappear {
            saveAPIKey()
            commitMaxTokens()
        }
    }

    // 写回 API Key：空则删除钥匙串条目，非空则保存
    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(service: ConfigStore.keychainService, account: ConfigStore.keychainAccount)
        } else {
            try? config.saveAPIKey(trimmed)
        }
    }

    // 提交最大 token：过滤为数字并夹到 100–8000
    private func commitMaxTokens() {
        let digits = maxTokensText.filter(\.isNumber)
        let value = Int(digits) ?? config.maxTokens
        let clamped = min(8000, max(100, value))
        config.maxTokens = clamped
        maxTokensText = String(clamped)
    }
}
