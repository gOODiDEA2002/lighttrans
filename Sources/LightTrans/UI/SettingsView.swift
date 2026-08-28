import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import LightTransCore

// 设置窗口（详细设计 13.2、v5 视觉基准）
// window.frame 520x450 pt（含标题栏），由 AppDelegate 控制；本视图填充内容区
struct SettingsView: View {
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

    private enum TestState: Equatable {
        case idle
        case testing
        case success(TimeInterval)
        case failed(String)
    }

    @ObservedObject private var config: ConfigStore = .shared
    #if DEBUG
    private let uiAcceptanceSnapshot: UIAcceptanceSettingsSnapshot?
    #endif
    @State private var selectedTab: SettingsTab = .api
    @State private var apiKey = ""
    @State private var hasEditedAPIKey = false
    @State private var apiKeySaveError: String?
    @State private var isKeyVisible = false
    @FocusState private var apiKeyFocused: Bool
    @State private var maxTokensText = ""
    @FocusState private var maxTokensFocused: Bool
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var isRevertingLaunch = false
    #if DEBUG
    @State private var apiBaseURLText = ""
    @State private var modelNameText = ""
    @State private var literalTemplateText = ""
    @State private var rewriteTemplateText = ""
    #endif
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var testGeneration: Int = 0

    init() {
        #if DEBUG
        self.uiAcceptanceSnapshot = nil
        #endif
    }

    #if DEBUG
    init(uiAcceptanceSnapshot: UIAcceptanceSettingsSnapshot) {
        self.uiAcceptanceSnapshot = uiAcceptanceSnapshot
        _config = ObservedObject(wrappedValue: ConfigStore.uiAcceptanceMock())
        let snapshot = uiAcceptanceSnapshot
            _selectedTab = State(initialValue: snapshot.selectedTab == .templates ? .templates : .api)
            _apiBaseURLText = State(initialValue: snapshot.apiBaseURL)
            _modelNameText = State(initialValue: snapshot.modelName)
            _apiKey = State(initialValue: snapshot.apiKey)
            _maxTokensText = State(initialValue: snapshot.maxTokensText)
            _literalTemplateText = State(initialValue: snapshot.literalTemplate)
            _rewriteTemplateText = State(initialValue: snapshot.rewriteTemplate)
            _testState = State(initialValue: Self.mapTestState(snapshot.testStatus))
    }
    #endif

    private var isFixtureMode: Bool {
        #if DEBUG
        return uiAcceptanceSnapshot != nil
        #else
        return false
        #endif
    }

    #if DEBUG
    private static func mapTestState(_ status: UIAcceptanceSettingsSnapshot.TestStatus) -> TestState {
        switch status {
        case .idle:
            return .idle
        case .testing:
            return .testing
        case .success(let milliseconds):
            return .success(TimeInterval(milliseconds) / 1000)
        case .failed(let message):
            return .failed(message)
        }
    }
    #endif

    private var apiBaseURLBinding: Binding<String> {
        #if DEBUG
        return isFixtureMode ? $apiBaseURLText : $config.apiBaseURL
        #else
        return $config.apiBaseURL
        #endif
    }

    private var modelNameBinding: Binding<String> {
        #if DEBUG
        return isFixtureMode ? $modelNameText : $config.modelName
        #else
        return $config.modelName
        #endif
    }

    private var literalTemplateBinding: Binding<String> {
        #if DEBUG
        return isFixtureMode ? $literalTemplateText : $config.literalPromptTemplate
        #else
        return $config.literalPromptTemplate
        #endif
    }

    private var rewriteTemplateBinding: Binding<String> {
        #if DEBUG
        return isFixtureMode ? $rewriteTemplateText : $config.promptTemplate
        #else
        return $config.promptTemplate
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: V5.Settings.sidebarContentWidth)
            Rectangle()
                .fill(V5.dividerColor)
                .frame(width: V5.Settings.dividerWidth)
            contentPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !isFixtureMode else { return }
            apiKey = config.loadAPIKey() ?? ""
            maxTokensText = String(config.maxTokens)
            let actual = LaunchAtLogin.isEnabled
            if actual != launchAtLogin {
                isRevertingLaunch = true
                launchAtLogin = actual
            }
        }
        .onDisappear {
            guard !isFixtureMode else { return }
            saveAPIKey()
            commitMaxTokens()
            testTask?.cancel()
        }
    }

    // MARK: - 侧边栏导航（v5：139 pt 内容 + 1 pt 分隔线 = 140 pt）

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: V5.titleFontSize))
                            .frame(width: 14)
                        Text(tab.rawValue)
                            .font(.system(size: V5.titleFontSize))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                            .fill(selectedTab == tab ? V5.accentBlue : Color.clear)
                    )
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(V5.cardFill)
    }

    // MARK: - 右侧内容区（v5：380 pt，内边距 16 pt）

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
        .padding(.leading, V5.contentPadding)
        .padding(.trailing, V5.contentPadding)
        .padding(.top, 19)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - 1. 接口配置页面（v5 基准 4.2）

    private var apiConfigView: some View {
        VStack(alignment: .leading, spacing: V5.Settings.fieldSpacing) {
            Text("接口配置")
                .font(.system(size: V5.pageTitleFontSize, weight: .semibold))
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("接口地址").font(.system(size: V5.settingsBodyFontSize))
                fixedHeightField(text: apiBaseURLBinding, secure: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("模型名").font(.system(size: V5.settingsBodyFontSize))
                fixedHeightField(text: modelNameBinding, secure: false)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("API Key").font(.system(size: V5.settingsBodyFontSize))
                HStack(spacing: 0) {
                    if isKeyVisible {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.plain)
                            .focused($apiKeyFocused)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.plain)
                            .focused($apiKeyFocused)
                    }
                    Button(action: { isKeyVisible.toggle() }) {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                            .frame(width: V5.Panel.copyIconSize, height: V5.Panel.copyIconSize)
                    }
                    .buttonStyle(.plain)
                    .help(isKeyVisible ? "隐藏 API Key" : "显示 API Key")
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                        .strokeBorder(V5.cardBorder, lineWidth: 1)
                )
                .onChange(of: apiKeyFocused) { _, focused in
                    if !focused { saveAPIKey() }
                }
                .onChange(of: apiKey) { _, _ in
                    if apiKeyFocused { hasEditedAPIKey = true }
                }
                if let apiKeySaveError {
                    Text(apiKeySaveError)
                        .font(.system(size: V5.captionFontSize))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("最大输出 Token").font(.system(size: V5.settingsBodyFontSize))
                fixedHeightField(text: $maxTokensText, secure: false)
                    .focused($maxTokensFocused)
                    .onChange(of: maxTokensFocused) { _, focused in
                        if !focused { commitMaxTokens() }
                    }
                    .onSubmit { commitMaxTokens() }
            }

            Divider()
                .padding(.vertical, 4)

            // 连通性测试（v5：标签+按钮+成功状态同行，长错误换下一行）
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("连通性测试")
                        .font(.system(size: V5.settingsBodyFontSize))

                    if testState == .testing {
                        Button(action: cancelTestConnection) {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small)
                                Text("取消测试")
                            }
                        }
                    } else {
                        Button(action: runTestConnection) {
                            Text("测试连接")
                        }
                    }

                    if case .success(let elapsed) = testState {
                        Text("当前配置连接成功（\(Int(elapsed * 1000)) ms）")
                            .font(.system(size: V5.captionFontSize))
                            .foregroundColor(V5.successGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(V5.successGreen.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if case .failed(let message) = testState {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(message)
                            .font(.system(size: V5.captionFontSize))
                            .foregroundColor(.red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("测试将发送极简请求，可能产生极微量 API 费用")
                    .font(.system(size: V5.captionFontSize))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func runTestConnection() {
        guard !isFixtureMode else { return }
        testTask?.cancel()
        testGeneration += 1
        let gen = testGeneration
        testState = .testing
        let currentBaseURL = apiBaseURLBinding.wrappedValue
        let currentModel = modelNameBinding.wrappedValue
        let currentKey = apiKey
        let service = TranslationService()

        testTask = Task { @MainActor in
            do {
                let elapsed = try await service.testConnection(
                    baseURL: currentBaseURL,
                    model: currentModel,
                    apiKey: currentKey
                )
                guard gen == testGeneration else { return }
                testState = .success(elapsed)
            } catch is CancellationError {
                guard gen == testGeneration else { return }
                testState = .idle
            } catch let error as TranslationError {
                guard gen == testGeneration else { return }
                testState = .failed(error.userMessage)
            } catch {
                guard gen == testGeneration else { return }
                testState = .failed("连接失败：\(error.localizedDescription)")
            }
        }
    }

    private func cancelTestConnection() {
        guard !isFixtureMode else { return }
        testGeneration += 1
        testTask?.cancel()
        testTask = nil
        testState = .idle
    }

    // MARK: - 2. 提示词模板页面（v5 基准 4.3：双模板同页，标题栏 34 pt）

    private var templatesConfigView: some View {
        VStack(alignment: .leading, spacing: V5.sectionSpacing) {
            Text("提示词模板")
                .font(.system(size: V5.pageTitleFontSize, weight: .semibold))
                .padding(.bottom, 2)

            templateCard(
                title: "直译提示词模板",
                icon: "character.book.closed",
                text: literalTemplateBinding
            )

            templateCard(
                title: "转写提示词模板",
                icon: "sparkles",
                text: rewriteTemplateBinding
            )
        }
    }

    // 单张模板卡片：标题栏 34 pt + 校验徽章 + 编辑区（v5 基准 4.3）
    @ViewBuilder private func templateCard(title: String, icon: String,
                                           text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: V5.titleFontSize, weight: .semibold))
                Spacer()
                templateBadge(for: text.wrappedValue)
            }
            .padding(.horizontal, 10)
            .frame(height: V5.Settings.templateTitleBarHeight)

            Divider()
                .padding(.horizontal, 8)

            TextEditor(text: text)
                .font(.system(size: V5.settingsBodyFontSize))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .background(TextEditorScrollConfigurator())
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .fill(V5.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous))
    }

    @ViewBuilder private func templateBadge(for template: String) -> some View {
        if template.contains("{{text}}") {
            Text("占位符 {{text}} 已就绪")
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(V5.successGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(V5.successGreen.opacity(0.12))
                .clipShape(Capsule())
        } else {
            Text("缺少 {{text}}")
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(V5.warningOrange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(V5.warningOrange.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - 3. 通用与快捷键页面

    private var generalConfigView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("通用与快捷键")
                .font(.system(size: V5.pageTitleFontSize, weight: .semibold))
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: V5.compactSpacing) {
                Text("呼出快捷键").font(.system(size: V5.titleFontSize, weight: .semibold))
                KeyboardShortcuts.Recorder("全局快捷键：", name: .togglePanel)
            }

            Divider()

            VStack(alignment: .leading, spacing: V5.compactSpacing) {
                Text("开机启动").font(.system(size: V5.titleFontSize, weight: .semibold))
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
                    Text(launchError).font(.system(size: V5.captionFontSize)).foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - 4. 历史记录页面

    private var historyConfigView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("历史记录")
                .font(.system(size: V5.pageTitleFontSize, weight: .semibold))
                .padding(.bottom, 2)

            Toggle("记录翻译历史", isOn: $config.historyEnabled)

            HStack(alignment: .top, spacing: V5.compactSpacing) {
                Image(systemName: ProcessSafeHistoryStore.shared.isICloudAvailable ? "icloud.fill" : "laptopcomputer")
                    .foregroundColor(.secondary)
                Text(ProcessSafeHistoryStore.shared.isICloudAvailable
                     ? "存储位置：iCloud 云盘（可多设备自动同步）"
                     : "存储位置：本机（未检测到 iCloud 云盘）")
                    .font(.system(size: V5.captionFontSize))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 辅助方法

    private func saveAPIKey() {
        guard !isFixtureMode, hasEditedAPIKey else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            config.deleteAPIKey()
            apiKeySaveError = nil
            hasEditedAPIKey = false
        } else {
            do {
                try config.saveAPIKey(trimmed)
                apiKeySaveError = nil
                hasEditedAPIKey = false
            } catch {
                apiKeySaveError = "API Key 保存失败，请重试"
            }
        }
    }

    private func commitMaxTokens() {
        guard !isFixtureMode else { return }
        let digits = maxTokensText.filter(\.isNumber)
        let value = Int(digits) ?? config.maxTokens
        let clamped = min(8000, max(100, value))
        config.maxTokens = clamped
        maxTokensText = String(clamped)
    }

    private func fixedHeightField(text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField("sk-...", text: text)
                    .textFieldStyle(.plain)
            } else {
                TextField("", text: text)
                    .textFieldStyle(.plain)
            }
        }
        .font(.system(size: V5.settingsBodyFontSize))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
    }
}

// 开机自启：基于 SMAppService.mainApp（决策 D-7）
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
