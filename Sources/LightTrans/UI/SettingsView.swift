import SwiftUI
import KeyboardShortcuts
import ServiceManagement

// 设置窗口（详细设计 13.2、UI 方案 v3.0）
struct SettingsView: View {
    // 侧边栏分类导航项（固定 4 项）
    enum SettingsTab: String, CaseIterable, Identifiable {
        case api = "接口配置"
        case templates = "提示词模板"
        case general = "通用与快捷键"
        case history = "历史记录"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .api: return "network"
            case .templates: return "square.and.pencil"
            case .general: return "command"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    // 连通性测试状态
    private enum TestState: Equatable {
        case idle
        case testing
        case success(TimeInterval)
        case failed(String)
    }

    @ObservedObject private var config = ConfigStore.shared
    @State private var selectedTab: SettingsTab = .api
    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @FocusState private var apiKeyFocused: Bool
    @State private var maxTokensText = ""
    @FocusState private var maxTokensFocused: Bool
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var isRevertingLaunch = false
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 140)
            Divider()
            contentPane
                .frame(width: 380)
        }
        .frame(width: 520, height: 450)
        .onAppear {
            apiKey = config.loadAPIKey() ?? ""
            maxTokensText = String(config.maxTokens)
            let actual = LaunchAtLogin.isEnabled
            if actual != launchAtLogin {
                isRevertingLaunch = true
                launchAtLogin = actual
            }
        }
        .onDisappear {
            saveAPIKey()
            commitMaxTokens()
            testTask?.cancel()
        }
    }

    // MARK: - 侧边栏导航（宽 140 pt）

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                            .frame(width: 16)
                        Text(tab.rawValue)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: - 右侧内容区（宽 380 pt）

    @ViewBuilder private var contentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch selectedTab {
            case .api:
                apiConfigView
            case .templates:
                templatesConfigView
            case .general:
                generalConfigView
            case .history:
                historyConfigView
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 1. 接口配置页面

    private var apiConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("接口配置")
                .font(.headline)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("接口地址").font(.subheadline)
                TextField("https://api.openai.com/v1", text: $config.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("模型名").font(.subheadline)
                TextField("deepseek-chat", text: $config.modelName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("API Key").font(.subheadline)
                HStack(spacing: 4) {
                    if isKeyVisible {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .focused($apiKeyFocused)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .focused($apiKeyFocused)
                    }
                    Button(action: { isKeyVisible.toggle() }) {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(isKeyVisible ? "隐藏 API Key" : "显示 API Key")
                }
                .onChange(of: apiKeyFocused) { _, focused in
                    if !focused { saveAPIKey() }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("最大输出 Token（100–8000）").font(.subheadline)
                TextField("2000", text: $maxTokensText)
                    .textFieldStyle(.roundedBorder)
                    .focused($maxTokensFocused)
                    .onChange(of: maxTokensFocused) { _, focused in
                        if !focused { commitMaxTokens() }
                    }
                    .onSubmit { commitMaxTokens() }
            }

            Divider()
                .padding(.vertical, 4)

            // 连通性测试操作行
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(action: runTestConnection) {
                        if testState == .testing {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("测试中…")
                            }
                        } else {
                            Text("测试连接")
                        }
                    }
                    .disabled(testState == .testing)

                    testStatusView
                }

                Text("测试将发送极简请求，可能产生极微量 API 费用")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder private var testStatusView: some View {
        switch testState {
        case .success(let elapsed):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("当前配置连接成功 (\(Int(elapsed * 1000))ms)")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        default:
            EmptyView()
        }
    }

    private func runTestConnection() {
        testTask?.cancel()
        testState = .testing
        let currentBaseURL = config.apiBaseURL
        let currentModel = config.modelName
        let currentKey = apiKey
        let service = TranslationService()

        testTask = Task { @MainActor in
            do {
                let elapsed = try await service.testConnection(
                    baseURL: currentBaseURL,
                    model: currentModel,
                    apiKey: currentKey
                )
                if Task.isCancelled { return }
                testState = .success(elapsed)
            } catch is CancellationError {
                // 取消静默
            } catch let error as TranslationError {
                if Task.isCancelled { return }
                testState = .failed(error.panelMessage)
            } catch {
                if Task.isCancelled { return }
                testState = .failed("连接失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 2. 提示词模板页面（双模板同页展示）

    private var templatesConfigView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("提示词模板")
                .font(.headline)
                .padding(.bottom, 2)

            // 直译模板卡片
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "character.book.closed")
                        .foregroundColor(.secondary)
                    Text("直译提示词模板")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    templateBadge(for: config.literalPromptTemplate)
                }
                TextEditor(text: $config.literalPromptTemplate)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }

            // 转写模板卡片
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.secondary)
                    Text("转写提示词模板")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    templateBadge(for: config.promptTemplate)
                }
                TextEditor(text: $config.promptTemplate)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            }
        }
    }

    @ViewBuilder private func templateBadge(for template: String) -> some View {
        if template.contains("{{text}}") {
            Text("占位符 {{text}} 已就绪")
                .font(.caption2)
                .foregroundColor(.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
        } else {
            Text("模板缺少 {{text}}")
                .font(.caption2)
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - 3. 通用与快捷键页面

    private var generalConfigView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("通用与快捷键")
                .font(.headline)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("呼出快捷键").font(.subheadline).bold()
                KeyboardShortcuts.Recorder("全局快捷键：", name: .togglePanel)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("开机启动").font(.subheadline).bold()
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if isRevertingLaunch { isRevertingLaunch = false; return }
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchError = nil
                        } catch {
                            launchError = "设置开机自启失败：\(error.localizedDescription)"
                            isRevertingLaunch = true
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - 4. 历史记录页面

    private var historyConfigView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("历史记录")
                .font(.headline)
                .padding(.bottom, 2)

            Toggle("记录翻译历史", isOn: $config.historyEnabled)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: HistoryStore.shared.isICloudAvailable ? "icloud.fill" : "laptopcomputer")
                    .foregroundColor(.secondary)
                Text(HistoryStore.shared.isICloudAvailable
                     ? "存储位置：iCloud 云盘（可多设备自动同步）"
                     : "存储位置：本机（未检测到 iCloud 云盘）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 辅助方法

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(service: ConfigStore.keychainService, account: ConfigStore.keychainAccount)
        } else {
            try? config.saveAPIKey(trimmed)
        }
    }

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
