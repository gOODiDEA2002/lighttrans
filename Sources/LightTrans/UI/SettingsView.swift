import SwiftUI
import KeyboardShortcuts
import ServiceManagement

// 设置窗口（详细设计第 5 节）。UserDefaults 项即改即存；仅 API Key 在失焦/关闭时写钥匙串。
struct SettingsView: View {
    @ObservedObject private var config = ConfigStore.shared
    @State private var apiKey = ""
    @FocusState private var apiKeyFocused: Bool
    @State private var maxTokensText = ""
    @FocusState private var maxTokensFocused: Bool
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var isRevertingLaunch = false

    private func templateMissingPlaceholder(_ template: String) -> Bool {
        !template.contains("{{text}}")
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

            Section("直译提示词模板") {
                TextEditor(text: $config.literalPromptTemplate)
                    .font(.system(size: 13))
                    .frame(height: 120)
                templateHint(for: config.literalPromptTemplate)
            }

            Section("转写提示词模板") {
                TextEditor(text: $config.promptTemplate)
                    .font(.system(size: 13))
                    .frame(height: 120)
                templateHint(for: config.promptTemplate)
            }

            Section("通用") {
                KeyboardShortcuts.Recorder("呼出翻译面板：", name: .togglePanel)
                Toggle("开机自启", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        // 程序化回弹触发的变更直接忽略，避免递归清掉刚显示的错误
                        if isRevertingLaunch { isRevertingLaunch = false; return }
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchError = nil
                        } catch {
                            launchError = "设置开机自启失败：\(error.localizedDescription)"
                            isRevertingLaunch = true
                            launchAtLogin = LaunchAtLogin.isEnabled   // 回弹到系统实际状态
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundColor(.red)
                }
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
            // 打开设置时与系统实际状态对齐；仅在值确有变化时设回弹守卫，避免吞掉后续用户操作
            let actual = LaunchAtLogin.isEnabled
            if actual != launchAtLogin {
                isRevertingLaunch = true
                launchAtLogin = actual
            }
        }
        .onDisappear {
            saveAPIKey()
            commitMaxTokens()
        }
    }

    // 模板下方提示：占位符说明；缺 {{text}} 时红字告知将追加原文
    @ViewBuilder private func templateHint(for template: String) -> some View {
        Text("用 {{text}} 表示待翻译的原文")
            .font(.caption)
            .foregroundColor(.secondary)
        if templateMissingPlaceholder(template) {
            Text("模板未包含 {{text}}，翻译时将把原文追加到模板末尾")
                .font(.caption)
                .foregroundColor(.red)
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

// 开机自启：基于 SMAppService.mainApp（决策 D-7）。状态实时读系统，不落库。
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled { try service.unregister() }
        }
    }
}
