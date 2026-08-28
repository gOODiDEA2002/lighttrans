# 系统设计文档

项目名：LightTrans（应用显示名：轻译）
文档版本：v1.4（2026-08-28）
关联文档：01-requirements.md（需求）、03-detailed-design.md（详细设计）、07-selection-translation-feature-design.md（选中文字翻译功能设计）、10-command-line-interface-detailed-design.md（CLI 详细设计）

## 1. 总体架构

产品包含 macOS 菜单栏 App 与独立 CLI 两个进程入口。两种入口通过 `LightTransCore` 共用完整翻译工作流；App 负责窗口与系统集成，CLI 负责参数、终端输出和信号。术语说明：下文的「层」只是代码分组方式，指互相之间通过明确接口调用、不直接修改对方内部数据的代码组。

```mermaid
flowchart TB
    subgraph APP[LightTrans App]
        A[状态栏图标 StatusItem]
        B[浮动翻译面板 FloatingPanel]
        C[设置窗口 SettingsWindow]
        C2[历史窗口 HistoryWindow]
        J[选中文字服务 SelectionServiceProvider]
    end
    subgraph CLI[lt CLI]
        K[参数与 stdin]
        L[stdout / stderr / SIGINT]
    end
    subgraph CORE[LightTransCore]
        W[TranslationWorkflow<br>模式 / 调度 / 取消 / 聚合 / 历史]
        D[TranslationService<br>提示词 / HTTP / SSE]
        E[SharedConfigurationProvider<br>UserDefaults + Keychain]
        I[ProcessSafeHistoryStore<br>跨进程串行追加与合并读取]
    end
    subgraph SYS[系统集成层]
        G[全局快捷键<br>KeyboardShortcuts 库]
        H[开机自启<br>SMAppService]
    end
    B --> W
    K --> W
    W --> D
    W --> E
    W --> I
    C2 --> I
    C --> E
    C --> H
    G --> B
    J --> B
    L --> K
    A --> B
    A --> C
    A --> C2
```

各层职责：

| 层 | 组件 | 职责 |
| --- | --- | --- |
| App 适配层 | AppDelegate、FloatingPanel、TranslatePanelView、SettingsView、HistoryWindowView、PanelViewModel | 状态栏、窗口、剪贴板、UI 状态与 Core 事件映射 |
| CLI 适配层 | LightTransCLI、CLIOptions、CLIInputReader、CLIOutputWriter、SignalCoordinator | 参数、标准输入、文本/JSON/NDJSON、标准错误、退出码与信号 |
| 共享核心层 | TranslationWorkflow、TranslationService、SharedConfigurationProvider、ProcessSafeHistoryStore | 配置快照、模型请求、路由、取消、聚合和历史记录 |
| 系统集成层 | KeyboardShortcuts、SMAppService、SelectionServiceProvider | 快捷键、开机自启与 macOS 服务选区 |

依赖方向固定为 App/CLI → `LightTransCore` → Foundation、Security、Darwin。Core 不依赖 AppKit、SwiftUI 或 KeyboardShortcuts；App 和 CLI 不得分别实现业务调度与历史聚合。

## 2. 关键技术决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D-1 | 用 Swift + SwiftUI 开发界面，AppKit（macOS 传统界面框架）管理状态栏与浮动面板，两者混合 | SwiftUI 写界面效率高；但纯 SwiftUI 的菜单栏方案 MenuBarExtra 没有公开接口支持"按快捷键以代码方式打开/关闭面板"，而这是本项目核心交互，故状态栏与面板下沉到 AppKit 手工管理，面板内容仍用 SwiftUI 绘制 |
| D-2 | 翻译面板用 NSPanel 浮动窗（Spotlight 样式，屏幕水平居中、垂直约上三分之一处） | 快捷键呼出的工具需要"浮在一切之上、失焦即隐藏、可跨全屏空间显示"，NSPanel 是系统为此类窗口提供的标准类型 |
| D-3 | 大模型接口按 OpenAI Chat Completions 风格（POST /chat/completions，stream 为 true）对接 | 只实现一种明确协议；服务端需要支持 Bearer Token、SSE 与 `choices[0].delta.content`，不承诺兼容所有自称 OpenAI-compatible 的实现 |
| D-4 | 全局快捷键采用第三方库 KeyboardShortcuts（sindresorhus/KeyboardShortcuts） | 系统未提供全局快捷键的现代公开接口；该库封装成熟，自带 SwiftUI 录制控件与 UserDefaults 持久化，接口用法已通过 Context7 于 2026-07-13 核验 |
| D-5 | 工程形态用 Swift Package Manager（Swift 官方的包与构建工具，下称 SPM）+ 打包脚本生成 .app，不建 Xcode 工程文件 | SPM 工程为纯文本、便于 AI 编码与版本管理；菜单栏应用所需的 .app 目录结构与 Info.plist 用脚本生成即可 |
| D-6 | 非敏感配置存 UserDefaults，API Key 存钥匙串 | UserDefaults 为明文属性列表文件，不可存密钥；钥匙串为系统加密存储 |
| D-7 | 开机自启用 SMAppService.mainApp（macOS 13 起的系统官方接口） | 无需辅助程序，一行注册一行注销 |
| D-8 | 源码公开；本机构建和 GitHub 未签名预览版均采用 ad-hoc 签名 | ad-hoc 签名不等同于 Developer ID 签名和 Apple 公证；预览版必须显式标注安全边界，不作为正式签名发行版 |
| D-9 | 历史记录经 iCloud 云盘文件夹（`~/Library/Mobile Documents/com~apple~CloudDocs/`，即用户在访达中看到的"iCloud 云盘"）同步，不使用 CloudKit | CloudKit（苹果面向应用的云数据库服务）需要付费开发者账号的授权，本项目无开发者账号；而 iCloud 云盘文件夹对程序而言就是一个由系统自动同步的普通文件夹，写文件不需要任何账号资质 |
| D-10 | 历史采用「每设备一个逻辑写入文件（JSON Lines）+ 同设备进程锁 + 读取时合并」的结构 | 不同设备不写同一文件；同一设备上的 App 与 CLI 使用 `flock` 和 `O_APPEND` 串行追加。旧版文件只读，新版写 v2 文件。 |
| D-11 | 一次翻译产出两段结果（直译 + 转写），对应两个可各自配置的提示词，两路请求并行发出、各自流式显示（增量 v1.1，详见详细设计第 11 节） | 直译看字面译法、转写做提示词工程改写，二者对同一原文互不依赖；并行发出让两段同时到达，用户无需等第一段结束。代价是单次翻译发两个请求、费用约翻倍，个人低频使用可接受 |
| D-12 | 选中文字的第一阶段入口采用主应用声明的 macOS 服务，只接收纯文本，不返回替换内容 | macOS 服务能通过请求专用 pasteboard 传递选区，不需要模拟复制或申请「辅助功能」权限；无返回值服务也不需要来源应用等待模型结果 |
| D-13 | 外部选区采用「最新请求优先」；已有翻译先停止并写入 `stopped` 历史，再开始新请求 | 直接取消并递增现有代次会让旧任务跳过历史写入；先完成停止状态保存可维持 FR-10 的完整记录规则 |
| D-14 | 选区不超过 `5,000` 个 Swift `Character` 时自动执行双路翻译；超过时只载入面板 | 现有 `maxTokens` 只限制结果长度，不能阻止误选长文产生两路输入费用；字符数判断无需引入模型专属分词依赖 |
| D-15 | `v0.1.0` 通过 GitHub Actions 构建 Apple Silicon（`arm64`）ZIP，并以 Pre-release 发布 | Tag 构建可复现且与源码一一对应；附件附带 SHA-256，工作流校验 Tag、应用版本、签名和处理器架构后才允许上传 |
| D-16 | CLI 采用独立可执行文件 `lt`，与 App 共用 `LightTransCore.TranslationWorkflow` | 保证除入口与呈现外的业务行为只有一份实现；App 未运行时 CLI 仍可工作 |
| D-17 | CLI 支持 `literal`、`rewrite`、`both`，默认 `both`；UI 固定使用 `both` | 单路调用只执行对应请求，双路保持现有并行语义；聚合只计算已请求路由 |
| D-18 | CLI 嵌入 `LightTrans.app/Contents/Helpers/lt` 并随 App 一起签名、校验和发布 | 防止 App、Core 与 CLI 版本分离；命令安装只创建指向包内 CLI 的安全符号链接 |

## 3. 核心数据流

一次翻译的共享链路：

```mermaid
sequenceDiagram
    participant E as App / lt 入口
    participant W as TranslationWorkflow
    participant C as 共享配置
    participant S as TranslationService
    participant M as 大模型接口
    participant H as ProcessSafeHistoryStore

    E->>W: run(text, mode)
    W->>C: 读取一次请求配置快照
    W->>S: 启动全部已请求路由
    S->>S: 模板中 {{text}} 替换为输入文字
    S->>M: POST {baseURL}/chat/completions（stream=true）
    loop 流式返回
        M-->>S: SSE 数据行（每行含一小段译文）
        S-->>W: 路由片段
        W-->>E: 串行 TranslationEvent
    end
    M-->>S: data:[DONE] 结束标记
    W->>C: 读取结束时历史开关
    W->>H: 追加一条聚合历史
    H-->>W: 写入完成、禁用或失败
    W-->>E: finished(summary)
```

说明：SSE（Server-Sent Events）是一种服务器分批推送文本的约定格式，响应体由若干以 `data: ` 开头的行组成，`data: [DONE]` 表示结束。解析细节见详细设计第 6 节。

翻译结束后（完成、停止或失败），共享工作流构造历史并交给进程安全的 HistoryStore。新 App 与 CLI 追加 v2 文件；旧文件保持只读兼容。历史窗口读入全部设备的 v1/v2 文件并按时间合并展示。细节见 CLI 详细设计第 12 节。

选中文字触发第一阶段服务时，数据流如下：

```mermaid
sequenceDiagram
    participant U as 用户
    participant A as 来源应用
    participant P as SelectionServiceProvider
    participant D as AppDelegate
    participant V as PanelViewModel
    participant H as HistoryStore

    U->>A: 选中文字并调用「轻译：打开面板」
    A->>P: 请求专用 pasteboard 中的纯文本
    P->>D: SelectionRequest(text)
    D->>V: acceptExternalText(text)
    alt 当前存在翻译任务
        V->>V: 取消并等待当前双路任务结束
        V->>H: 追加 stopped 历史
    end
    alt 文字不超过 5,000 字符
        V->>V: 写入输入并启动双路翻译
    else 文字超过 5,000 字符
        V->>V: 只写入输入并显示费用保护提示
    end
    D->>D: 显示或保持翻译面板
```

## 4. 铁律清单（硬约束，方案与编码不得违反）

| 编号 | 约束 | 出处 |
| --- | --- | --- |
| L-1 | 运行环境为本机 macOS 15.7.4；最低部署目标定为 macOS 14 | `sw_vers` 实测，2026-07-13 |
| L-2 | Info.plist 必须设 LSUIElement 为 true（应用不出现在 Dock）；由此设置窗口打开前必须先调用 NSApp.activate，否则窗口不获焦、无法输入 | Apple 平台惯例，LSUIElement 应用的已知行为 |
| L-3 | KeyboardShortcuts 库接口：`KeyboardShortcuts.Name("id", default: .init(.t, modifiers: [.option]))` 定义默认快捷键；`KeyboardShortcuts.events(for:)` 异步序列监听；`KeyboardShortcuts.Recorder` 为 SwiftUI 录制控件 | Context7 文档核验，2026-07-13；参数标签经 T1 实测订正：`from: "2.0.0"` 解析到的发布版为 2.4.0，其初始化器为 `init(_:default:)`（Context7 展示的 `initial:` 为未发布版改名，尚未进入任何 2.x 发布版），故以 `default:` 为准 |
| L-4 | OpenAI 兼容流式接口：请求体含 `stream: true`；响应为 SSE，译文片段位于每条 JSON 的 `choices[0].delta.content`；`data: [DONE]` 为结束标记 | OpenAI API 公开规范 |
| L-5 | API Key 只能经 KeychainHelper 读写（kSecClassGenericPassword 类型），禁止出现在 UserDefaults、日志与任何源码文件中 | 需求 FR-7 |
| L-6 | 提示词模板占位符固定为 `{{text}}`，替换采用纯字符串替换，不做任何模板语法解析 | 保持实现最简 |
| L-7 | 无付费开发者账号：禁止使用任何需要 iCloud 授权（entitlement）的能力（CloudKit、NSUbiquitousKeyValueStore、专属 iCloud 容器等），历史同步只允许走 iCloud 云盘文件夹的普通文件读写 | 需求文档第 2 节；苹果规定 iCloud 授权仅对付费开发者账号开放 |
| L-8 | 历史文件按设备隔离：不同设备禁止写同一文件；同一设备上的 App 与 CLI 只能持本机 `flock` 后用 `O_APPEND` 追加 v2 文件。旧文件不得迁移、改写或删除 | 决策 D-10、CLI 详细设计第 12 节 |
| L-9 | 目标机器不保证安装完整 Xcode，构建流程不得依赖 `PreviewsMacros`。`KeyboardShortcuts 2.4.0` 固定到修订 `1aef8557`，构建前用版本匹配的补丁删除 `Recorder.swift` 中仅供开发预览的三个 `#Preview` 块，运行时代码不得改动 | 2026-07-15 清理 `.build` 后实测：未处理预览代码时 Command Line Tools 构建失败；删除预览块后干净构建通过 |
| L-10 | FR-12 第一阶段只接收纯文本，不声明服务返回类型，不读取或修改通用剪贴板，不申请「辅助功能」权限 | FR-12、选中文字翻译功能设计 R-1、R-5 |
| L-11 | 自动翻译上限固定为 `5,000` 个 Swift `Character`；超出时只载入原文，不截断、不自动请求 | 选中文字翻译功能设计 R-3 |
| L-12 | 新服务请求到达时，正在进行的任务必须先以 `stopped` 状态完成历史写入；禁止直接用新代次使旧任务跳过保存 | 决策 D-13、选中文字翻译功能设计 R-4 |
| L-13 | Terminal、iTerm2 和其他终端应用永久禁止自动粘贴和原位替换 | 选中文字翻译功能设计 R-6 |
| L-14 | 未取得 Developer ID 证书前，GitHub 二进制必须标记为未签名预览版和 Pre-release；不得省略架构、SHA-256、Gatekeeper 提示或来源核验说明 | 决策 D-8、D-15 |
| L-15 | UI 与 CLI 必须调用同一 `TranslationWorkflow`；路由调度、取消、聚合和历史构造只能存在一份 | FR-16、决策 D-16 |
| L-16 | 同一次调用的全部已请求路由使用同一配置快照；历史开关在结束时读取 | CLI 详细设计第 7、9 节 |
| L-17 | CLI 收到 `Ctrl+C` 后必须等待 `stopped` 历史处理结束再退出；`SIGKILL` 除外 | FR-16、CLI 详细设计第 11 节 |
| L-18 | CLI 的 stdout 只承载结果协议，stderr 只承载诊断；两者均禁止 API Key | CLI 详细设计第 11、14 节 |
| L-19 | CLI 必须嵌入 App 并与 App 同次构建、签名和发布；禁止单独发布版本不一致的 CLI | 决策 D-18 |
| L-20 | 首次生成 `deviceID` 时必须使用本机跨进程锁；并发首次启动不得产生多个本机历史文件后缀 | FR-16、CLI 详细设计第 7、12 节 |

## 5. 假设与验证结论

| 编号 | 假设 | 验证方式 | 不成立时的备选 |
| --- | --- | --- | --- |
| A-1 | NSPanel 设为不抢占激活（nonactivatingPanel）并重写 canBecomeKey 后，输入框可正常输入中文（含输入法候选） | 实施计划任务 T5 中真机验证（结论：成立，中文输入法含候选窗正常，无需备选） | 改为常规激活式面板（呼出时激活本应用，隐藏时归还焦点） |
| A-2 | KeyboardShortcuts 库支持最低部署目标 macOS 14 | T1 结论：成立；当前锁定 2.4.0 与修订 `1aef8557` | 锁定该库的兼容旧版本，或将部署目标提高到其要求的版本（本机 15.7.4，余量充足） |
| A-3 | SPM 构建产物经脚本打包成 .app 后，SMAppService 开机自启注册可用（该接口对应用所在路径可能有要求） | 任务 T9 真机验证：注册后重新登录检查（结论：成立，应用置于 /Applications 后开关注册无错误、系统登录项可见、注销重登自动启动） | 退化为提示用户手动将应用加入"登录项"，开关仅作跳转引导 |
| A-4 | 非沙盒的 ad-hoc 签名应用可直接读写 iCloud 云盘文件夹路径（`~/Library/Mobile Documents/com~apple~CloudDocs/`），至多出现一次性的系统授权弹窗 | 任务 T7 真机验证：写入后在访达"iCloud 云盘"中确认文件出现并开始同步（结论：成立，直接读写成功、无授权弹窗；退化到本机目录亦经强制走本机分支验证通过） | 改为将历史目录设为用户可选路径，由用户手动选到 iCloud 云盘内；或退化为仅存本机 |
| A-5 | 其他设备同步来的历史文件若被系统"优化储存空间"驱逐为云端占位（本地只留 `.icloud` 占位文件），应用可触发下载或至少能识别并提示 | 任务 T7 验证：对占位文件调用 FileManager 的下载接口观察行为（结论：可测部分成立，`.icloud` 占位文件被识别、计入 pendingDevices、调用 startDownloadingUbiquitousItem 不崩溃；真实跨设备占位下载需第二台设备，标注待验，同 FR-11） | 历史窗口对未下载的设备文件显示"该设备记录待从 iCloud 下载"提示，引导用户在访达中下载 |
| A-6 | 主应用声明的 `NSServices` 能被系统识别，并能在轻译未运行时启动 `LSUIElement` 应用 | T17 结论：成立；Release 安装、服务刷新和 Safari 冷启动通过 | 评估独立 `.service` 包；未经设计评审不实施 |
| A-7 | 不授予「辅助功能」权限时，目标应用可以把纯文本选区发送给第一阶段服务 | T17 结论：在已验收应用中成立；来源应用不暴露系统服务时按兼容性边界处理 | 对不支持的应用保留手动复制流程，不自动改用 Accessibility API |
| A-8 | 服务请求可以在应用完成面板初始化后安全切换到主线程处理 | T17 结论：成立；冷启动、后台运行和面板已显示状态通过 | 调整服务注册时机，并使用单条冷启动请求缓存 |
| A-9 | 多行文字、Emoji、组合字符和中英文混排可通过纯文本 pasteboard 无损传递 | T17 结论：成立；单元测试与真机样例通过 | 记录不兼容应用；禁止静默截断或替换字符 |
| A-10 | Terminal 和 iTerm2 的只读选区能调用无返回值文本服务 | T17 结论：成立；人工补验通过 | 标记为不支持，保留复制后呼出面板的流程 |
| A-11 | 当前双路任务取消后，在不递增代次的前提下等待协调任务结束，可以稳定写入一条 `stopped` 历史 | T17 结论：成立；任务生命周期测试与真实流式替换通过 | 先重构任务结束协议，不接入正式服务入口 |
| A-12 | Release CLI 能读取 App 保存的同一 UserDefaults 域和钥匙串条目 | T21 在干净安装环境验证 App 保存后 CLI 读取与真实请求 | 停止实施，重新评估 App 代理方案；不得改用命令参数传密钥 |
| A-13 | Release App 与 CLI 能通过同一本机锁文件协调历史追加 | T21 运行 App 等价写入者与多个 CLI 并发测试 | 停止 Release 接入，检查签名、路径和 POSIX 错误 |
| A-14 | 持锁进程被 `SIGKILL` 后内核会释放 `flock` | T21 用辅助进程持锁并强制终止，再由新进程获取 | 改为带所有者恢复协议的锁并更新设计，禁止永久等待 |
| A-15 | iCloud 目录中的 v2 历史文件可以在本机锁保护下稳定追加 | T21 在受控真实目录执行并发写入与合并读取 | 重新评审 App 代理写入，不关闭 CLI 历史 |
| A-16 | v1 与 v2 历史文件合并不会改变去重和排序 | T21 构造重复 ID、坏尾行和跨时区数据集 | 修订读取规则，不迁移或改写旧文件 |
| A-17 | `Contents/Helpers/lt` 可以通过严格签名、架构和 ZIP 往返校验 | T21 本地与 CI 使用同一发布脚本验证 | 调整标准嵌套位置和签名顺序，不单独发布 CLI |

## 6. 模块间接口概览

- App 与 CLI 的唯一业务入口是 `TranslationWorkflow.run(request:emit:) -> TranslationSummary`；两种适配层只消费事件和最终摘要。
- 工作流到网络层使用 `TranslationService.translate(text:template:configuration:) -> AsyncThrowingStream<String, Error>`，网络层不得直接读取 App 配置。
- 设置窗口是配置的唯一写入方；CLI 只读同一 UserDefaults 域和钥匙串条目。
- 历史读写入口是异步 `ProcessSafeHistoryStore.append(_:)` 与 `loadAll()`；工作流是唯一历史构造者。
- 错误统一为 Core 的稳定错误码与消息。历史写入失败不改变翻译状态，只记录诊断。
- 来源应用到系统集成层只有一个入口：`SelectionServiceProvider` 从请求专用 pasteboard 读取纯文本并生成不可变请求；它不得调用模型接口或写历史。
- `AppDelegate` 接收选区请求并交给 `PanelViewModel.acceptExternalText(_:)`；ViewModel 管理长文本与最新请求优先，任务取消、双路启动和历史保存由共享工作流完成。
