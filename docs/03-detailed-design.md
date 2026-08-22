# 详细设计文档

项目名：mac-translator（应用显示名：轻译 / LightTrans）
文档版本：v1.6（2026-08-22）
关联文档：02-system-design.md（系统设计）、04-implementation-plan.md（实施计划）、07-selection-translation-feature-design.md（选中文字翻译功能设计）

本文档是编码的直接依据。编码时如遇本文档未覆盖的决策点，停下补充设计并经确认后再继续，不得在代码中即兴决定。

## 1. 工程结构

```
mac-translator/
├── Package.swift                      # SPM 工程定义
├── Sources/
│   └── LightTrans/
│       ├── LightTransApp.swift        # 程序入口（@main），挂接 AppDelegate
│       ├── AppDelegate.swift          # 状态栏、面板、设置窗口、快捷键监听的总管
│       ├── SelectionServiceProvider.swift # macOS 服务：读取外部应用发送的纯文本选区
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
├── Patches/
│   └── KeyboardShortcuts-2.4.0-remove-previews.patch  # 移除依赖中的 Xcode 预览代码
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
    //    循环正常结束后按 Task.isCancelled 区分：被取消(stopTranslate)则回到 .idle 并保留部分译文，
    //    否则 state = .done；捕获 TranslationError 则 state = .failed(其中文文案)。
    //    说明（T4/T6 实测订正）：经消费端 Task.cancel() 取消时，AsyncThrowingStream 的 for-await 循环
    //    直接结束、不抛 CancellationError，故取消判定用 Task.isCancelled，不能依赖 catch CancellationError
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

1. 执行 `swift package resolve`，确认 `KeyboardShortcuts` 的修订号与 `Package.resolved` 中固定的 `1aef8557` 一致。
2. 若 `Recorder.swift` 中仍含 `#Preview`，应用 `Patches/KeyboardShortcuts-2.4.0-remove-previews.patch`；补丁只删除三个开发预览块，不修改运行时代码（铁律 L-9）。修订号或补丁上下文不匹配时停止并报错，不继续编译。
3. 执行 `swift build -c release`。
4. 组装 `build/LightTrans.app/Contents/{MacOS,Resources}` 目录结构。
5. 复制可执行文件至 `Contents/MacOS/LightTrans`；复制 Info.plist 至 `Contents/`。
6. `codesign --force --sign - build/LightTrans.app`（ad-hoc 签名）。
7. 输出产物路径。脚本任何一步失败立即退出并报错（`set -euo pipefail`）。

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

## 11. 增量 v1.1：双段翻译（直译 + 转写）

对应系统设计决策 D-11。一次翻译从"一个提示词、一段结果"改为"两个提示词、两段结果"：第一段直译，第二段转写（提示词工程改写）。两路请求并行发出、各自流式显示。本节列出对第 2、4、6、10 节的全部改动，编码以本节为准；未提及处保持 v1.0 不变。

### 11.1 配置项（对第 2 节的增补）

新增一个提示词模板，原有 `promptTemplate` 语义收敛为"转写模板"。

| 配置项 | 键名 | 存储 | 类型 | 默认值 |
| --- | --- | --- | --- | --- |
| 直译提示词模板 | literalPromptTemplate | UserDefaults | String | 见 11.1.1（即 v1.0 的默认直译模板） |
| 转写提示词模板 | promptTemplate（沿用原键名） | UserDefaults | String | 见 11.1.2 |

说明：沿用 `promptTemplate` 原键名，使已保存转写提示词的用户配置无缝保留；新增的 `literalPromptTemplate` 在老用户机器上从未写入，读到 register 默认值即直译模板。maxTokens、接口地址、模型名、API Key 两段共用，不新增。

#### 11.1.1 直译默认模板

```
你是专业翻译。请翻译下面这段文字：如果原文以中文为主，翻译成英文；否则翻译成简体中文。只输出译文本身，不要任何解释或多余内容。

{{text}}
```

#### 11.1.2 转写默认模板（新装机器的初值）

```
你是提示词工程专家。请把下面这段文字改写成一段结构清晰、指令明确的英文提示词，可直接交给大模型使用。只输出改写后的提示词本身，不要任何解释。

{{text}}
```

### 11.2 TranslationService（对第 6 节的改动）

入口签名增加模板参数，由调用方传入具体模板；其余流程（校验、渲染、请求、SSE 解析、取消、错误映射）不变。

```swift
func translate(text: String, template: String) -> AsyncThrowingStream<String, Error>
```

第 6.1 节第 2 步的"读 config.promptTemplate"改为使用传入的 `template`；`{{text}}` 替换与不含占位符时的兜底拼接规则不变（铁律 L-6）。

### 11.3 PanelViewModel（对第 4.2 节的改动）

由"单结果 + 单状态 + 单任务"改为"双结果 + 双状态 + 并行两任务 + 一个协调任务"。

```swift
enum PartState: Equatable { case idle, translating, done, stopped, failed(String) }

@Published var inputText: String
@Published var literalResult: String     // 直译结果
@Published var rewriteResult: String     // 转写结果
@Published var literalState: PartState
@Published var rewriteState: PartState
var isTranslating: Bool                   // 任一段处于 translating 即为 true

func startTranslate()
// 1. 输入为空忽略；进行中先取消
// 2. generation += 1；清空两段结果，两段状态置 .translating
// 3. 启动一个协调任务，内部用 async let 并行跑两段（直译用 literalPromptTemplate，转写用 promptTemplate）：
//    每段各自消费 service.translate(text:template:) 的流，逐片段写入对应结果串；
//    循环正常结束按 Task.isCancelled 区分 .stopped / .done；捕获 TranslationError 置 .failed(中文文案)。
//    （取消判定沿用 4.2 的结论：for-await 被取消时直接结束、不抛 CancellationError）
// 4. 两段都结束后，若 generation 未被新翻译顶替，写入一条历史记录（含两段译文，见 11.4）

func stopTranslate()          // 取消协调任务，连带取消两段的底层网络
func copy(_ text: String)     // 复制指定文本到剪贴板（直译、转写各自调用）
```

聚合状态（写历史用）：任一段 failed 记 `failed`（error 为各失败段文案的合并），否则任一段 stopped 记 `stopped`，否则 `done`。历史开关关闭时不写。写入失败仍只记日志，不打扰用户（同 10.4）。

### 11.4 历史记录格式（对第 10.3 节的改动，向后兼容）

`HistoryRecord` 扩展为可同时承载单段（老记录）与双段（新记录）：`output` 改为可选并保留以兼容 v1.0 老记录；新增可选的 `literalOutput`、`rewriteOutput`。

```swift
struct HistoryRecord: Codable, Identifiable {
    let id, time, device, model, status, input: String
    let output: String?          // v1.0 单段译文，仅老记录存在
    let literalOutput: String?   // 直译（v1.1 新记录）
    let rewriteOutput: String?   // 转写（v1.1 新记录）
    let error: String?
}
```

- 编码：Swift 合成的 Codable 对 nil 可选字段自动省略键，故新记录只写 `literalOutput`/`rewriteOutput`，老记录只写 `output`，两种行都能被同一结构解码。
- 历史窗口详情：有 `literalOutput`/`rewriteOutput` 则分"直译""转写"两块展示，各带复制；否则回退显示单段 `output`（老记录）。
- 关键字过滤：匹配范围扩展到 `input`、`output`、`literalOutput`、`rewriteOutput`。

### 11.5 界面（对第 4 节的改动）

- 面板高度由 440 提升至 600（`FloatingPanel` 初始尺寸与 `TranslatePanelView` 的 frame 同步调整），宽度仍 560。
- 结果区由一块改为上下两块，各含小标题（"直译""转写"）、该段状态（翻译中… / 失败红字）、独立滚动的只读可选文本、独立"复制"按钮（点击后按钮文案变"已复制"，1.5 秒还原）。两块平分结果区剩余高度。
- 操作行仍为 Cmd+Return 触发的"翻译/停止"按钮；翻译中任一段可停止（一次停止同时中断两段）。
- 面板隐藏不重置任何状态（FR-9 不变）。

## 12. 增量 v1.2：应用图标与一键安装更新

本节补充应用图标资源和本机安装流程。只调整应用包资源与工程脚本，不改变运行时业务逻辑、配置存储或历史记录格式。

### 12.1 应用图标

- 视觉方向：采用彩色折纸造型，主体由青色、紫色与橙色渐变构成，表达「轻量、转换与语言重组」。图标以用户指定的最终素材为准。
- 构图：只保留内圈玻璃圆角方块，将其居中放大至接近画布边缘，四周保留约 5% 的均匀边距；折纸主体不得被裁切。
- 源文件：`Resources/AppIcon.png`，尺寸固定为 1024 x 1024。内圈玻璃方块之外必须使用透明像素，使 macOS 按圆角轮廓显示图标。
- 应用资源：`Resources/AppIcon.icns`。`Scripts/generate-app-icon.sh` 使用系统自带的 `sips` 和 `iconutil`，从源文件生成 macOS 所需的 16 至 1024 像素图层；不引入第三方依赖。
- `Info.plist` 增加 `CFBundleIconFile = AppIcon.icns`；打包时将 `AppIcon.icns` 复制到应用包的 `Contents/Resources/`。

### 12.2 打包脚本调整

`Scripts/build-app.sh` 保持第 8.2 节原有流程，并增加以下步骤：

1. 打包前确认 `Resources/AppIcon.icns` 存在。
2. 将图标复制到 `Contents/Resources/AppIcon.icns`。
3. 签名后用 `codesign --verify --deep --strict` 校验应用包，避免把签名不完整的产物交给安装脚本。

### 12.3 一键安装或更新

新增 `Scripts/install-app.sh`，执行 `bash Scripts/install-app.sh` 后完成构建、安装或更新，并重新启动应用。

1. 先调用 `Scripts/build-app.sh` 生成并校验新的应用包。
2. 默认安装到 `/Applications/LightTrans.app`；可通过环境变量 `LIGHTTRANS_INSTALL_DIR` 覆盖安装目录，避免将环境路径写死在脚本逻辑中。
3. 若检测到目标路径中的 LightTrans 正在运行，先请求应用正常退出；超时后只终止该路径对应的进程，不按进程名扩大范围。
4. 新应用先复制到安装目录内的临时目录并再次校验，再将旧版本移到同目录备份位置，最后切换为新版本。切换失败时恢复旧版本，避免留下不完整的应用包。
5. 安装目录不可直接写入时使用 `sudo` 完成文件替换；构建和启动仍以当前用户执行。
6. 安装成功后删除临时文件和旧版本备份，清除本地应用包的隔离标记并启动应用。UserDefaults、钥匙串和历史记录均位于应用包之外，更新时保持不变。

## 13. 增量 v1.3：UI 界面与交互重构

本节补充 UI 优化方案（docs/06-ui-optimization-proposal.md）确立的界面与交互规格。保持既有配置项、钥匙串存取与历史记录 JSON Lines 存储协议完全不变。

### 13.1 浮动翻译面板规格（TranslatePanelView & FloatingPanel）

- **窗口与材质**：`FloatingPanel` 固定为 `560 × 600 pt`，圆角 `14 pt`，背景应用 `NSVisualEffectView`（材质为 `.popover`，`blendingMode = .behindWindow`）。
- **垂直布局预算**：
  - 四周内边距：`14 pt`（内部可用高 `572 pt`）。
  - 输入卡片：高 `100 pt`，内部含 TextEditor、字符统计（如「82 字符」）与一键清空按钮（`xmark.circle.fill`，翻译中禁用）。
  - Esc 键：始终绑定隐藏面板（`FloatingPanel.cancelOperation` 调 `orderOut`），不作清空。
  - 操作栏：高 `28 pt`，空闲时为强调色「翻译 ⌘↩」；生成中切换为警示样式「停止」（带 `stop.fill` 图标），左侧配 ProgressView 与「正在生成…」。
  - 双段结果卡片（直译与转写）：平分剩余高度各约 `190 pt`，各自独立滚动。头部展示单色图标（`character.book.closed` 与 `sparkles`）及局部状态（「正在直译…」/「已完成」/「失败：文案」）。复制按钮带 1.5 秒绿色 checkmark「已复制」反馈。
  - 底部辅助栏：高 `20 pt`，左侧显示「⌘↩ 翻译 · Esc 隐藏」；右侧提供设置与历史直达图标按钮。
- **依赖注入**：`TranslatePanelView` 声明 `onOpenSettings: () -> Void` 与 `onOpenHistory: () -> Void` 闭包，由 `AppDelegate` 创建时注入。

### 13.2 设置窗口规格（SettingsView & TranslationService）

- **窗口与导航**：固定 `520 × 450 pt`，采用侧边栏真实分页导航（左侧宽 `140 pt`，右侧宽 `380 pt`），固定 4 个分类：
  1. 接口配置（`network`）
  2. 提示词模板（`square.and.pencil`）
  3. 通用与快捷键（`command`）
  4. 历史记录（`clock.arrow.circlepath`）
- **接口配置**：
  - 模型名为自由输入的 `TextField`。
  - API Key 提供明暗文切换（`eye` / `eye.slash`），仅在失焦或关闭时持久化。
  - 连通性测试契约（`TranslationService.testConnection`）：
    - 请求：`POST {baseURL}/chat/completions`，Header 携带 `Authorization: Bearer {apiKey}` 与 `Content-Type: application/json`；
    - 请求体：`stream: false`，`max_tokens: 5`，`messages: [{"role": "user", "content": "Reply with OK."}]`；
    - 超时：10 秒；支持调用端 `Task.cancel()` 立即中断底层 URLSession 请求；
    - 成功判定：收到 HTTP 2xx 且能成功解码 `choices[0].message.content`（非空字符串），记录请求发出至解析完成的毫秒耗时（如 `185ms`）；
    - 错误归类：非 2xx 与网络错误按第 7 节映射为 `TranslationError`；2xx 但 JSON 不符合契约映射为 `badResponse`；
    - 隔离性：测试仅使用当前表单内存中正在编辑的值，**不保存至 UserDefaults / Keychain，绝对不调用 HistoryStore 写入历史记录**；
    - 界面反馈：按钮旁展示进度指示器或「当前配置连接成功 (xxx ms)」/ 红色错误文案，并注明「测试将发送极简请求，可能产生极微量 API 费用」；`SettingsView` 持有独立测试 Task，窗口关闭或重新发起测试时自动取消。
- **提示词模板**：同页纵向完整展示「直译提示词模板」与「转写提示词模板」，各带 `{{text}}` 校验徽章（绿色就绪 / 橙色缺失）。

### 13.3 历史记录窗口规格（HistoryWindowView）

- **窗口与分栏**：固定初始 `680 × 480 pt`，左侧列表 `270 pt`，右侧详情 `410 pt`。
- **列表项**：摘要通过 `.lineLimit(2)` 限制为最多 2 行；左侧使用微型语义色点（绿/橙/红）并提供无障碍标签；设备名使用低对比度次要文本。
- **搜索与选中联动**：
  - 搜索框展示匹配计数；
  - `selectedRecord = filtered.first { $0.id == selectedID }`；
  - 筛选后旧选中项仍在结果中则保留；若被过滤且有其他匹配项则自动选中首项；无结果时置 `selectedID = nil` 并展示空状态占位。
- **详情区元数据**：2 行网格排版（Row 1: 时间 + 状态 Badge；Row 2: 设备 + 模型，采用尾部截断与 hover tooltip）。原文、直译、转写分 3 卡片独立展示与复制。

### 13.4 输入框可调高度与菜单栏图标规格（增量 v1.4）

- **输入框下拉放大（TranslatePanelView）**：
  - 默认高度 `100 pt`，动态拉伸范围 `[70 pt, 240 pt]`；
  - 位于输入卡片底部中心配备 `36 × 4 pt` 胶囊拖拽手柄（Resize Handle），悬停高亮并展示垂直调整光标（`.resizeUpDown`）；
  - 手柄使用 AppKit 原生 `NSView`（通过 `NSViewRepresentable` 桥接），override `mouseDownCanMoveWindow` 返回 `false`，防止 `FloatingPanel.isMovableByWindowBackground = true` 时窗口背景拖动吞掉手柄的鼠标事件；面板其余背景区域仍可正常拖动窗口；
  - 支持 `mouseDown`/`mouseDragged`/`mouseUp` 实时拖拽拉大/缩小；双击手柄快速弹性动画复位至默认 `100 pt`；
  - 布局弹性分配：输入框变高时，下方双结果卡平分剩余高度并保持内部 `ScrollView` 平滑滚动，面板总高严格维持 `600 pt`。
- **菜单栏状态图标精细化（AppDelegate）**：
  - 选用 `translate`（一级入口优先表达翻译语义），配置 `NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)`；
  - 保留 `character.bubble` 回退（兼容旧系统无 `translate` 的情况）；`sparkles.rectangle.stack` 作为已评估但未采用的候选方案。
  - 启用 `isTemplate = true`，自动适配深浅色桌面壁纸及点击高亮。

### 13.5 跨窗口视觉一致性规则（增量 v1.5）

以下视觉语言在翻译面板、设置窗口和历史窗口中保持统一（详见 `docs/06-ui-optimization-proposal.md` v4.0 第 3.7 节）：

1. 外层卡片容器统一使用圆角 8–10 pt、`controlBackgroundColor` 半透明填充与 `Color.primary.opacity(0.06–0.08)` 描边。
2. 标题栏统一使用 SF Symbols 单色图标（12 pt）+ 标题（13 pt semibold）+ 操作按钮靠右。
3. 复制按钮统一采用紧凑方形图标按钮（`doc.on.doc`），复制后原位切换绿色 `checkmark`，不显示"已复制"文字，1.5 秒后还原；tooltip 在未复制时显示"复制{标题}"，复制后显示"已复制"。本条规则覆盖 13.1 等早期章节中关于复制按钮文案变为"已复制"的旧描述，以紧凑图标为准。
4. 状态色统一使用完成绿、停止橙、失败红，状态点附带 VoiceOver 无障碍标签。
5. 拖拽手柄提供无障碍标签、当前高度值和可调整动作（AXAction），调整步长 10 pt。

## 14. 增量 v1.6：选中文字后打开翻译面板

本节实现 FR-12 的第一阶段，只提供 `轻译：打开面板`。单路翻译并复制、原位替换、Accessibility API、浏览器扩展和终端自动输入均不在 T17 范围内。

产品行为、后续阶段和兼容性门槛以 `docs/07-selection-translation-feature-design.md` 为准。本节固定第一阶段的文件、接口、任务顺序和状态变化。

### 14.1 文件范围

| 文件 | 改动 |
| --- | --- |
| `Resources/Info.plist` | 声明一个接收纯文本、无返回类型的 `NSServices` 服务 |
| `Sources/LightTrans/SelectionServiceProvider.swift` | 新增服务提供者，读取请求专用 pasteboard 并生成不可变请求 |
| `Sources/LightTrans/AppDelegate.swift` | 持有并注册服务提供者；接收请求后显示面板 |
| `Sources/LightTrans/UI/PanelViewModel.swift` | 接收外部文字；处理长文本、连续请求、停止状态和历史写入 |
| `Sources/LightTrans/UI/TranslatePanelView.swift` | 在现有操作栏显示长文本费用保护提示，不改变面板几何尺寸 |
| `Tests/LightTransTests/SelectionRequestTests.swift` | 覆盖纯文本校验、字符上限和最新请求优先 |
| `Tests/LightTransTests/PanelExternalInputTests.swift` | 覆盖任务停止、历史写入顺序和外部文字载入 |

不得修改 `TranslationService` 的请求协议、配置键、历史 JSON Lines 字段或现有窗口尺寸。

### 14.2 Info.plist 服务声明

在主应用 `Info.plist` 增加以下结构：

```xml
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>
        <dict>
            <key>default</key>
            <string>轻译：打开面板</string>
        </dict>
        <key>NSMessage</key>
        <string>openPanelWithSelectedText</string>
        <key>NSPortName</key>
        <string>LightTrans</string>
        <key>NSSendTypes</key>
        <array>
            <string>public.utf8-plain-text</string>
        </array>
        <key>NSRequiredContext</key>
        <dict/>
        <key>NSUserData</key>
        <string>openPanel</string>
    </dict>
</array>
```

第一阶段禁止声明以下键：

- `NSReturnTypes`：第一阶段不向来源应用返回替换内容。
- `NSTimeout`：无返回值服务不等待模型结果。
- `NSKeyEquivalent`：避免与来源应用或其他系统服务的快捷键冲突。
- `NSRestricted`：服务只处理调用方主动提供的纯文本，不读取文件或执行路径。

应用仍使用现有 `LSUIElement = true`、ad-hoc 签名和主应用包，不新增 App Extension 或独立 `.service` 包。

### 14.3 SelectionServiceProvider

新增不可变请求：

```swift
struct SelectionRequest: Sendable {
    let text: String
    let receivedAt: Date
}
```

服务提供者接口：

```swift
final class SelectionServiceProvider: NSObject {
    var onRequest: (@MainActor (SelectionRequest) -> Void)?

    @objc func openPanelWithSelectedText(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    )
}
```

处理规则：

1. 只用 `pasteboard.string(forType: .string)` 读取纯文本。
2. 读取失败时设置 `error.pointee = "未收到可处理的文本"`，不调用 `onRequest`。
3. 用 `trimmingCharacters(in: .whitespacesAndNewlines)` 只判断是否为空；传给请求的 `text` 必须保留原始首尾空格和换行。
4. 仅空白时直接返回，不打开面板、不写历史、不发起请求。
5. 有效文本封装为 `SelectionRequest`，通过 `Task { @MainActor in ... }` 交给主线程。
6. 把请求交给主线程后立即结束服务方法；不得在服务方法内等待模型响应。
7. 不读取通用剪贴板，不记录正文，不调用 `TranslationService` 或 `HistoryStore`。

### 14.4 AppDelegate 注册与面板显示

`AppDelegate` 增加对 `SelectionServiceProvider` 的强引用。正式启动顺序固定为：

1. `setupStatusItem()`
2. `setupPanel()`
3. `setupSelectionService()`
4. `startShortcutListener()`

`setupSelectionService()` 的职责：

```swift
private func setupSelectionService() {
    let provider = SelectionServiceProvider()
    provider.onRequest = { [weak self] request in
        self?.handleSelectionRequest(request)
    }
    selectionServiceProvider = provider
    NSApp.servicesProvider = provider
    NSUpdateDynamicServices()
}
```

必须在面板和 `PanelViewModel` 初始化完成后设置 `NSApp.servicesProvider`。系统设置服务提供者后可能立即发送请求，提前注册会产生冷启动空引用。

`handleSelectionRequest(_:)` 的顺序：

1. 调用 `panelViewModel.acceptExternalText(request.text)`。
2. 面板隐藏时，按现有规则定位到鼠标所在屏幕。
3. 面板已经显示时保留当前位置，禁止因重复服务请求跳回默认位置。
4. 调用 `makeKeyAndOrderFront(nil)`。
5. 发送 `.panelDidShow`，让输入框获得焦点。

该入口是「显示」语义，不复用 `togglePanel()`；面板已显示时不得被服务请求反向隐藏。

DEBUG UI 验收启动分支不得注册系统服务，避免截图进程污染正式服务列表。

### 14.5 PanelViewModel 外部请求状态

新增常量和状态：

```swift
static let selectionAutoTranslateCharacterLimit = 5_000

@Published var selectionNotice: String?
private var latestSelectionRequestID: UInt64 = 0
```

新增入口：

```swift
func acceptExternalText(_ text: String)
```

每次调用时执行：

1. `latestSelectionRequestID += 1`，当前值作为本次 `requestID`。
2. 创建主线程 Task 处理请求，不立即改变现有 `generation`。
3. 若当前正在翻译，先把 `currentTask` 捕获为局部常量，再取消并等待该任务结束；不得在挂起后重新读取可能已指向新任务的属性。
4. 等待期间若出现更新请求，旧 Task 在继续前比较 `requestID == latestSelectionRequestID`；不相等则结束，不载入旧文字。
5. 当前协调任务结束后必须已经完成一次 `stopped` 历史写入；只有此后才能载入最新文字。
6. 清空两路旧结果与状态，把原始 `text` 写入 `inputText`。
7. 字符数不超过 `5,000` 时清空 `selectionNotice` 并调用 `startTranslate()`。
8. 字符数超过 `5,000` 时不调用模型，设置 `selectionNotice = "选中文字超过 5,000 字符，请确认后翻译"`。

任务生命周期同时作以下订正：

- `runPart` 捕获 `CancellationError` 时，若代次仍有效，必须把对应分段状态设为 `.stopped`，不得保留 `.translating`。
- 协调任务只负责一次历史写入；写入完成后，在代次仍有效时把 `currentTask` 置为 `nil`。
- `startTranslate()` 开始时清空 `selectionNotice`。
- 手动停止和外部请求停止均通过相同协调任务写历史，不得从外部入口直接调用 `HistoryStore.append`。
- 载入超长选区后，手动点击「翻译」或按 `Command+Return` 直接执行，不增加第二次确认。

### 14.6 TranslatePanelView 提示位置

保持操作栏 `28 pt` 高度和现有按钮尺寸，不新增垂直区域：

- 翻译中：左侧继续显示 `ProgressView` 和「正在生成…」，忽略 `selectionNotice`。
- 未翻译且 `selectionNotice != nil`：用左侧原有空白位置显示提示，使用 `caption` 和 `.secondary`，单行尾部截断，并通过 `.help(selectionNotice)` 提供完整文本。
- 未翻译且没有提示：保持现有空白。
- 开始翻译、清空输入或收到新的普通选区时清除提示。

提示不得改变输入卡、两张结果卡、底部栏和窗口总高度，T16 视觉基准仍然有效。

### 14.7 历史、剪贴板与日志

- 正常选区产生的历史与面板手动双路翻译一致。
- 因新服务请求停止的旧任务写为 `stopped`，保留两路已收到的部分结果。
- 超长选区在手动开始前不写历史。
- 历史开关关闭时不写记录，但任务替换顺序保持不变。
- 第一阶段禁止读取、清空或写入 `NSPasteboard.general`。
- 请求专用 pasteboard 只在服务方法内读取，不保存引用。
- 日志只记录服务请求接收、空文本、字符上限分支和错误类别；不得记录原文、结果或 pasteboard 内容。
- 第一阶段不记录来源应用名称、窗口标题、文档 URL 或进程信息。

### 14.8 第一阶段验证

T17 必须先验证系统设计 A-6 至 A-11，再完成正式接入。验证范围：

1. `Info.plist` 可通过 `plutil -lint`，系统服务列表能识别 `轻译：打开面板`。
2. 轻译未运行、后台运行、面板已显示三种状态均能收到选区。
3. 不授予「辅助功能」权限时，兼容应用仍能工作。
4. 中文、英文、多行、Emoji、组合字符、首尾空格能无损进入输入框。
5. `4,999`、`5,000`、`5,001` 个 `Character` 分别覆盖自动执行边界。
6. 翻译中连续触发两次，新旧历史数量、状态、原文和结果均正确，最终只执行最新选区。
7. 第一阶段前后 `NSPasteboard.general.changeCount` 和内容不变。
8. 配置缺失、断网、单路失败、手动停止、面板隐藏的行为与现有面板一致。
9. 对 `docs/07-selection-translation-feature-design.md` 第 13 节列出的已安装应用执行完整兼容性检查。
10. 运行单元测试、Debug/Release 构建、应用打包、严格签名和现有 UI 视觉回归。

### 14.9 后续阶段边界

- FR-14 的单路翻译并复制不得在 T17 顺带实现。
- FR-15 的原位替换必须先通过功能设计第 8.2 节全部门槛，再补充本详细设计。
- 未经新的设计确认，不得增加 `NSReturnTypes`、Accessibility API、模拟键盘、通知权限或终端输入能力。
