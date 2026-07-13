# 详细设计文档

项目名：mac-translator（应用显示名：轻译 / LightTrans）
文档版本：v1.0（2026-07-13）
关联文档：02-system-design.md（系统设计）、04-implementation-plan.md（实施计划）

本文档是编码的直接依据。编码时如遇本文档未覆盖的决策点，停下补充设计并经确认后再继续，不得在代码中即兴决定。

## 1. 工程结构

```
mac-translator/
├── Package.swift                      # SPM 工程定义
├── Sources/
│   └── LightTrans/
│       ├── LightTransApp.swift        # 程序入口（@main），挂接 AppDelegate
│       ├── AppDelegate.swift          # 状态栏、面板、设置窗口、快捷键监听的总管
│       ├── UI/
│       │   ├── FloatingPanel.swift    # NSPanel 子类：浮动面板窗体
│       │   ├── TranslatePanelView.swift  # SwiftUI：面板内容
│       │   ├── PanelViewModel.swift   # 面板状态与翻译调度（ObservableObject）
│       │   ├── SettingsView.swift     # SwiftUI：设置窗口内容
│       │   └── HistoryWindowView.swift   # SwiftUI：历史窗口内容
│       ├── Services/
│       │   └── TranslationService.swift  # 接口调用与 SSE 解析
│       ├── Storage/
│       │   └── HistoryStore.swift     # 历史记录追加写入与合并读取
│       └── Config/
│           ├── ConfigStore.swift      # 配置读写（UserDefaults）
│           └── KeychainHelper.swift   # 钥匙串读写
├── Resources/
│   └── Info.plist                     # 打包用属性列表模板
├── Scripts/
│   └── build-app.sh                   # 构建并打包 .app 的脚本
├── docs/                              # 设计文档（本目录）
└── README.md
```

### 1.1 Package.swift 要点

- swift-tools-version 5.9 及以上；`platforms: [.macOS(.v14)]`。
- 单一可执行 target `LightTrans`。
- 依赖：`https://github.com/sindresorhus/KeyboardShortcuts`（版本按 `from: "2.0.0"` 起解析，若与 macOS 14 部署目标冲突，按系统设计假设 A-2 的备选处理）。

## 2. 配置项设计

| 配置项 | 键名 | 存储位置 | 类型 | 默认值 |
| --- | --- | --- | --- | --- |
| 接口地址 | apiBaseURL | UserDefaults | String | `https://api.openai.com/v1` |
| 模型名 | modelName | UserDefaults | String | 空字符串（强制用户填写） |
| 提示词模板 | promptTemplate | UserDefaults | String | 见 2.1 |
| 最大输出 token | maxTokens | UserDefaults | Int | 2000 |
| API Key | 服务名 `LightTrans`、账户名 `apiKey` | 钥匙串 | String | 无 |
| 历史记录开关 | historyEnabled | UserDefaults | Bool | true |
| 设备标识 | deviceID | UserDefaults | String | 首次启动生成的 UUID，此后不变（见 10.2） |
| 全局快捷键 | 由 KeyboardShortcuts 库自管 | UserDefaults（库自动处理） | — | Option+T |
| 开机自启 | 不落库，实时读 SMAppService.mainApp.status | 系统 | Bool | 关 |

### 2.1 默认提示词模板

```
你是专业翻译。请翻译下面这段文字：如果原文以中文为主，翻译成英文；否则翻译成简体中文。只输出译文本身，不要任何解释或多余内容。

{{text}}
```

### 2.2 ConfigStore 接口

```swift
// 配置读写的唯一入口，界面层与服务层均通过它取配置
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()
    @Published var apiBaseURL: String      // didSet 写回 UserDefaults
    @Published var modelName: String
    @Published var promptTemplate: String
    @Published var maxTokens: Int
    // API Key 不作属性缓存，每次经 KeychainHelper 即取即用
    func loadAPIKey() -> String?
    func saveAPIKey(_ key: String) throws
}
```

### 2.3 KeychainHelper 接口

```swift
// 钥匙串通用密码（kSecClassGenericPassword）的最小封装
enum KeychainHelper {
    static func read(service: String, account: String) -> String?
    static func save(_ value: String, service: String, account: String) throws
    static func delete(service: String, account: String)
}
```

实现要点：save 采用先删后加（SecItemDelete 后 SecItemAdd），避免处理"已存在则更新"的分支；读取失败一律返回 nil，不抛错。

## 3. 程序入口与 AppDelegate

### 3.1 LightTransApp.swift

```swift
@main
struct LightTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }   // 占位，不使用 SwiftUI 的 Settings 场景
    }
}
```

### 3.2 AppDelegate 职责与接口

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    func applicationDidFinishLaunching(_:)
    // 1. 创建 statusItem：图标用系统符号 "character.bubble"
    //    左键 -> togglePanel()；右键 -> 弹出 NSMenu（历史记录…、设置…、退出）
    // 2. 创建 panel（内容为 TranslatePanelView，尺寸见第 4 节）
    // 3. 启动快捷键监听：
    //    for await _ in KeyboardShortcuts.events(.keyDown, for: .togglePanel) { togglePanel() }

    func togglePanel()
    // 显示逻辑：定位到当前含鼠标的屏幕，水平居中、顶部向下 22% 处；
    // makeKeyAndOrderFront 并将焦点置于输入框。已显示则 orderOut 隐藏。

    func openSettings()
    // 惰性创建 settingsWindow（NSWindow + NSHostingView(SettingsView)）；
    // 先 NSApp.activate(ignoringOtherApps: true) 再 makeKeyAndOrderFront（铁律 L-2）

    func openHistory()
    // 同 openSettings 的窗口管理方式，内容为 HistoryWindowView（见第 10.5 节）
}

extension KeyboardShortcuts.Name {
    // 参数标签为 default:（对齐 KeyboardShortcuts 2.4.0 的 init(_:default:)，详见系统设计铁律 L-3）
    static let togglePanel = Self("togglePanel", default: .init(.t, modifiers: [.option]))
}
```

## 4. 浮动面板

### 4.1 FloatingPanel（NSPanel 子类）

| 属性 | 取值 | 目的 |
| --- | --- | --- |
| styleMask | [.nonactivatingPanel, .titled, .fullSizeContentView] | 呼出时不打断当前应用的激活状态；隐藏标题栏视觉 |
| titleVisibility / titlebarAppearsTransparent | .hidden / true | 无边框观感 |
| level | .floating | 浮于普通窗口之上 |
| collectionBehavior | [.canJoinAllSpaces, .fullScreenAuxiliary] | 在任何桌面空间与全屏应用上均可呼出 |
| isMovableByWindowBackground | true | 可拖动 |
| canBecomeKey（重写） | true | 允许输入框获得焦点（对应假设 A-1，任务 T5 先验证中文输入） |
| resignKey()（重写） | 调 orderOut 隐藏 | 实现失焦自动隐藏（FR-9） |

尺寸：宽 560，高度由内容自适应，最小 220。

### 4.2 PanelViewModel

```swift
@MainActor
final class PanelViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var resultText: String = ""
    @Published var state: PanelState = .idle   // idle / translating / done / failed(String)
    private var currentTask: Task<Void, Never>?

    func startTranslate()
    // 1. 输入为空则忽略；正在翻译则先 cancel
    // 2. 清空 resultText，state = .translating
    // 3. currentTask = Task { for try await chunk in service.translate(...) { resultText += chunk } }
    //    正常结束 state = .done；捕获 CancellationError 静默；
    //    捕获 TranslationError 则 state = .failed(其中文文案)
    // 4. 无论完成、停止还是失败，结束时调用 HistoryStore.append 写入历史记录
    //    （historyEnabled 为 false 时跳过；写入失败只记日志，不打扰用户）

    func stopTranslate()   // currentTask?.cancel()
    func copyResult()      // NSPasteboard 写入 resultText
}
```

### 4.3 TranslatePanelView 界面规格

自上而下：

1. 输入区：`TextEditor`，占位提示"输入要翻译的文字，Cmd+Return 开始翻译"，最小高度 90，最大高度 200（超出滚动）。
2. 操作行：左侧状态文案（翻译中… / 错误文案，错误用系统红色），右侧"翻译"按钮（translating 状态下变为"停止"）。翻译触发绑定 Cmd+Return（`.keyboardShortcut(.return, modifiers: .command)`）。
3. 结果区：只读文本，可选中，最小高度 90，最大高度 320（超出滚动）；右上角复制按钮，点击后按钮文案变为"已复制"，1.5 秒后还原。
4. Esc 键：隐藏面板（通过 onExitCommand 或 keyDown 监听实现，交由编码时按 SwiftUI 可用能力选择，行为以"按 Esc 面板消失"为准）。

面板隐藏不重置任何状态（FR-9）。

## 5. 设置窗口（SettingsView）

单页 Form，宽 480，分三组：

1. 接口：接口地址（TextField）、模型名（TextField）、API Key（SecureField，显示时从钥匙串读入内存，失焦或点保存时写回钥匙串）、最大输出 token（TextField，限数字，范围 100–8000）。
2. 提示词模板：TextEditor，高 140；下方灰色小字说明"用 {{text}} 表示待翻译的原文"。若保存时模板不含 `{{text}}`，红字提示且不阻止保存（运行时按第 6.1 节兜底）。
3. 通用：快捷键录制（`KeyboardShortcuts.Recorder("呼出翻译面板：", name: .togglePanel)`）、开机自启（Toggle，绑定 SMAppService，注册失败时红字显示错误并回弹开关）。
4. 历史记录：记录开关（Toggle，绑定 historyEnabled）；下方灰色小字显示当前历史存储位置及状态（"iCloud 云盘（可多设备同步）"或"本机（未检测到 iCloud 云盘）"，判定逻辑见 10.3）。

所有 UserDefaults 项即改即存，无单独保存按钮；仅 API Key 有明确的写入时机（失焦/保存）。

## 6. TranslationService

### 6.1 接口与流程

```swift
struct TranslationService {
    func translate(text: String) -> AsyncThrowingStream<String, Error>
}
```

流程：

1. 读配置。校验：接口地址非空且可构成 URL，模型名非空，API Key 存在；不满足抛 `TranslationError.notConfigured`。
2. 渲染提示词：`template.replacingOccurrences(of: "{{text}}", with: text)`；若模板不含占位符，则以"模板 + 空行 + 原文"拼接兜底。
3. 构造请求：

```
POST {apiBaseURL}/chat/completions
Authorization: Bearer {apiKey}
Content-Type: application/json

{
  "model": "{modelName}",
  "stream": true,
  "max_tokens": {maxTokens},
  "messages": [ { "role": "user", "content": "{渲染后的提示词}" } ]
}
```

请求超时 60 秒。apiBaseURL 末尾多余的 `/` 需去除后再拼接路径。

4. 用 `URLSession.shared.bytes(for:)` 获取逐行字节流，按第 6.2 节解析，每解析出一段译文即向流内 yield。
5. HTTP 状态码非 2xx：读取响应体（尽力解析其中的 error.message），按第 7 节映射为 TranslationError 抛出。

### 6.2 SSE 解析规则

对响应体逐行处理：

- 空行、非 `data: ` 开头的行：跳过。
- `data: [DONE]`：正常结束流。
- 其余 `data: {json}` 行：解码 JSON，取 `choices[0].delta.content`（String，可能缺失），存在且非空则 yield。解码失败的单行跳过并继续，不中断整个流。

响应 JSON 解码只需一个最小模型：

```swift
struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}
```

### 6.3 取消

调用方（PanelViewModel）取消 Task 时，AsyncThrowingStream 的 onTermination 中取消底层 URLSession 任务，确保连接立即断开、不再计费输出。

## 7. 错误设计

```swift
enum TranslationError: Error {
    case notConfigured        // 配置缺失
    case invalidKey           // HTTP 401
    case rateLimited          // HTTP 429
    case insufficientQuota    // HTTP 402，或响应体 error.code 含 insufficient
    case badURL               // 地址无法解析 / HTTP 404
    case network(String)      // URLError（断网、超时、无法连接）
    case badResponse(String)  // 其他非 2xx 或响应格式异常
}
```

界面文案映射：

| 错误 | 面板显示文案 |
| --- | --- |
| notConfigured | 请先在设置中填写接口地址、模型名和 API Key |
| invalidKey | API Key 无效，请检查设置 |
| rateLimited | 请求过于频繁，请稍后再试 |
| insufficientQuota | 账户余额不足或额度已用完 |
| badURL | 接口地址不正确，请检查设置 |
| network | 网络连接失败，请检查网络后重试 |
| badResponse | 接口返回异常：{摘要，截断至 100 字} |

## 8. Info.plist 与打包

### 8.1 Info.plist 关键键

| 键 | 值 |
| --- | --- |
| CFBundleIdentifier | com.andy.lighttrans |
| CFBundleName / CFBundleDisplayName | LightTrans / 轻译 |
| CFBundleExecutable | LightTrans |
| CFBundleShortVersionString | 0.1.0 |
| LSUIElement | true（铁律 L-2） |
| LSMinimumSystemVersion | 14.0 |
| NSHumanReadableCopyright | 个人工具，仅本机使用 |

### 8.2 build-app.sh 步骤

1. `swift build -c release`。
2. 组装 `build/LightTrans.app/Contents/{MacOS,Resources}` 目录结构。
3. 复制可执行文件至 `Contents/MacOS/LightTrans`；复制 Info.plist 至 `Contents/`。
4. `codesign --force --sign - build/LightTrans.app`（ad-hoc 签名）。
5. 输出产物路径。脚本任何一步失败立即退出并报错（`set -euo pipefail`）。

安装方式：将 `build/LightTrans.app` 拷贝到 `/Applications` 后启动（开机自启功能要求应用位于稳定路径，对应假设 A-3）。

## 9. 日志

仅使用系统统一日志（os.Logger，子系统 com.andy.lighttrans）记录：请求开始/结束/失败原因（不含正文与密钥）。不写自定义日志文件。历史正文只写入历史文件（第 10 节），不进日志。

## 10. 历史记录模块（HistoryStore）

设计依据：系统设计决策 D-9、D-10，铁律 L-7、L-8。核心结构：每台设备只追加写入自己的历史文件，文件放在 iCloud 云盘文件夹内由系统同步；显示时读入全部设备的文件合并排序。

### 10.1 存储位置

| 场景 | 目录 |
| --- | --- |
| iCloud 云盘可用 | `~/Library/Mobile Documents/com~apple~CloudDocs/LightTrans/history/` |
| 不可用（未登录或未开启 iCloud 云盘） | `~/Library/Application Support/LightTrans/history/` |

可用性判定：`~/Library/Mobile Documents/com~apple~CloudDocs/` 目录存在即视为可用；应用启动时判定一次并缓存，目录不存在时自动使用本机目录，不弹窗打扰。首次写入时自动创建 `LightTrans/history/` 子目录。

### 10.2 设备标识与文件命名

- 首次启动生成 UUID 存入 UserDefaults（键 deviceID），此后永不改变；取其前 8 位作为文件名后缀。
- 本机历史文件名：`history-{deviceID 前 8 位}.jsonl`。本机只允许写这一个文件（铁律 L-8）。
- 记录内另存人类可读的设备名（`Host.current().localizedName`，即"系统设置 - 通用 - 关于本机"中的电脑名称），供历史窗口显示；文件名不用设备名，避免用户改名导致双文件。

### 10.3 记录格式（JSON Lines）

每行一条独立 JSON，UTF-8 编码，字段如下：

```json
{"id":"550E8400-...","time":"2026-07-13T21:35:02+08:00","device":"Andy 的 MacBook Pro","model":"deepseek-chat","status":"done","input":"原始输入全文","output":"译文全文"}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | String | 记录的 UUID，作为合并时的去重键 |
| time | String | ISO 8601 格式，含时区偏移；跨设备合并按此排序 |
| device | String | 写入时的电脑名称 |
| model | String | 本次使用的模型名 |
| status | String | done（完成）/ stopped（手动停止，output 为已收到的部分译文）/ failed（失败，output 为空，附加 error 字段存中文错误文案） |
| input / output | String | 原始输入与输出全文，不截断 |

写入方式：将记录序列化为单行 JSON（禁止美化换行），追加写入并以换行符结尾；用 FileHandle 追加模式实现。JSON 序列化天然转义正文中的换行符，保证一行一条不破坏格式。

### 10.4 HistoryStore 接口

```swift
struct HistoryRecord: Codable, Identifiable { /* 10.3 的字段 */ }

final class HistoryStore {
    static let shared = HistoryStore()
    func append(_ record: HistoryRecord)
    // 追加到本机文件；任何失败（磁盘满、权限等）仅记日志，不抛给调用方

    func loadAll() -> (records: [HistoryRecord], pendingDevices: Int)
    // 枚举 history 目录下所有 history-*.jsonl，逐行解码（坏行跳过并记日志），
    // 按 id 去重、按 time 倒序返回；
    // 目录中若存在 .icloud 占位文件（其他设备的记录尚未从云端下载到本机），
    // 先调用 FileManager.default.startDownloadingUbiquitousItem 尝试触发下载，
    // 并以 pendingDevices 计数返回，供界面提示（对应系统设计假设 A-5）
}
```

### 10.5 历史窗口（HistoryWindowView）界面规格

窗口 680 x 480，可调大小，自上而下：

1. 工具栏：关键字过滤输入框（对 input 与 output 做包含匹配，即时过滤）、刷新按钮（重新 loadAll）。
2. 记录列表：按时间倒序，每行显示时间（格式 `MM-dd HH:mm`）、设备名、输入摘要（首行，截断至约 60 字）。当 pendingDevices 大于 0 时，列表顶部显示灰色提示"另有 N 台设备的记录待从 iCloud 下载"。
3. 详情区（选中某行后显示，与列表左右分栏，列表占约 40% 宽）：完整原文与译文上下排列，均可选中复制，各带复制按钮；显示完整时间、设备、模型、状态（stopped 显示"已中途停止"，failed 显示错误文案）。

第一期不做删除与导出；文件为通用 JSON Lines 格式，必要时可直接用文本工具查看。

### 10.6 前提与边界（写给使用者）

- 多设备同步的前提：各电脑登录同一 Apple ID 且系统设置中开启 iCloud 云盘；同步时效由系统决定，通常数秒至数分钟。
- 历史含翻译原文与译文，存于用户自己的 iCloud 空间，除 iCloud 本身外不经任何第三方。
