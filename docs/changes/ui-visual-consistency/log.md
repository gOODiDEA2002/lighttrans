# 变更日志——T16 UI 视觉一致性与交互精修

> 只记录技术决策、失败原因和可复用发现，不记录普通操作流水。

## 时间线

| 时间 | 阶段 | 事件 | 备注 |
| --- | --- | --- | --- |
| 2026-08-21 | propose | 完成原始设计与当前实现差异检查 | 发现设计资产过时、测试取消缺失、历史搜索归属不符 |
| 2026-08-21 | apply | 用户授权编写排工并交由 Cursor 实现 | Cursor 不提交，Codex 负责最终验收 |
| 2026-08-21 | implement | WP-A 至 WP-E 全部完成 | git diff --check / swift build / Release 打包 / 严格签名全部通过（实现方自检） |
| 2026-08-21 | review | Codex 首轮独立审查发现 6 项问题 | 竞态/眼睛按钮/设备名溢出/光标失配/文档不一致/13.5 覆盖声明 |
| 2026-08-21 | fix | Cursor 回修全部 6 项 | 代码 4 项 + 文档 2 项，重新自检通过 |
| 2026-08-21 | review | Codex 二次审查发现 1 项问题 | 复制按钮 try? 吞掉 CancellationError 导致连续点击时旧任务清除新 checkmark |
| 2026-08-21 | fix | Cursor 回修第 7 项 | TranslatePanelView.ResultSection + HistoryWindowView.DetailCard 改为 do/catch return |
| 2026-08-21 | verify | Codex 完成独立静态与构建验收 | diff、Debug、Release、严格签名通过；真机 UI 状态矩阵待验收 |
| 2026-08-21 | reject | 用户真机验收打回 T16 | 输入高度拖拽带动窗口移动；当前 UI 与设计资产差异明显 |
| 2026-08-21 | review | Codex 完成像素对齐返工评审 | 确认拖拽事件竞争，并发现设计资产与 v4 规范存在多处冲突 |
| 2026-08-21 | fix | WP-1 手柄改为 AppKit NSViewRepresentable | mouseDownCanMoveWindow=false，阻止窗口背景拖动吞掉手柄事件 |
| 2026-08-21 | approve | 用户确认 v5 唯一视觉基准 | 基准规范转为已确认；8 张 2× PNG 写入 `docs/assets/v5/`，旧概念稿归档 |
| 2026-08-21 | implement | WP-3 全量视觉返工 | 新增 DesignTokens.swift 收敛 v5 token；TranslatePanelView/SettingsView/HistoryWindowView/AppDelegate 全部对齐 v5 基准尺寸、字号、圆角、间距和颜色；历史窗口改为两行搜索头部、64pt 行高、带文字复制按钮和固定分栏；面板新增局部失败引导文案 |
| 2026-08-21 | reject | Codex 验收 WP-3 发现 3 项阻塞 | 1) 浮动面板 CGWindow 560x628 非目标 560x600；2) 历史窗口 frame 680x508 非目标 680x480；3) 历史列表仍为默认蓝色选中态。原因：NSHostingView 默认 sizingOptions 把 intrinsicContentSize 反推给窗口 |
| 2026-08-21 | fix | 修正 WP-3 三项阻塞 | 面板 SwiftUI 根改为 fill 而非固定尺寸；三窗口 hosting view 统一 sizingOptions=[]；历史列表确认 ScrollView+LazyVStack 已正确使用 token |
| 2026-08-21 | implement | WP-4 Debug UI 验收态完成 | 新增 Debug-only `UIAcceptanceState` 和 `--ui-acceptance-state`，覆盖 19 个冻结状态；设置/历史视图支持快照注入，冻结态不触发真实网络，且不读写真实持久化 |
| 2026-08-21 | implement | WP-4 截图脚本完成 | 新增 `Scripts/capture-ui-acceptance.sh`，逐状态启动 Debug app，按 PID 捕获窗口，校验 frame 与截图尺寸，输出到 `build/ui-acceptance` |
| 2026-08-21 | verify | WP-4 构建与截图验收通过 | `git diff --check`、`swift test`、`swift build`、`build-app`、`codesign`、截图脚本全部通过；真实鼠标拖拽手感仍待人工最终验收 |
| 2026-08-21 | reject | Codex 复验打回（P1） | 缺少强制 dark/2x 证据；冻结文案与 v5 不一致；streaming 停止按钮受默认键盘按钮样式影响；TextEditor 滚动区域不一致；DEBUG 隔离不完整；缺少菜单栏三态证据 |
| 2026-08-21 | fix | WP-4 P1 回修 | DEBUG 验收窗口强制 darkAqua 并输出环境日志；脚本校验 dark+2x；冻结文案改为对齐 v5；停止按钮改为确定性红色警示样式；隐藏 TextEditor 滚动指示器；验收类型与工厂收口到 DEBUG；菜单栏补充 dark/light 证据并将 pressed 标记 manual-required |
| 2026-08-21 | verify | WP-4 P1 回修验证 | `git diff --check`、`swift test`、`swift build`、`build-app`、`codesign`、截图脚本再次通过；菜单栏 pressed 与真实鼠标拖拽仍需人工门禁 |
| 2026-08-21 | verify | Codex 真实拖拽门禁关闭 | 已验证 `100→240`、`100→70`，窗口 frame 固定 `(1000,221,560,600)`，原点 delta=`(0,0)` |
| 2026-08-21 | fix | 第三轮像素对齐回修 | 面板加深语义底色并重排输入区内边距；设置侧栏防换行与 26pt 输入容器；历史区按 76/64/72/104 几何预算重排；菜单栏改为真实 `NSStatusItem` rect + `screencapture` + CGEvent 按压采集；脚本新增 overlay 产物 |
| 2026-08-21 | verify | 第三轮复跑 | `git diff --check`、`swift test`、`swift build`、`build-app`、`capture-ui-acceptance.sh` 均通过；视觉是否收敛仍待 Codex 叠图复验，菜单栏 pressed 继续保留 manual-required 门禁 |
| 2026-08-21 | reject | Codex 第三轮复验未通过（剩余定点） | 面板暗层级仍偏亮、设置整体上偏、历史 metadata 卡高未填满、菜单栏 rect 坐标链路错误导致 82x4 无效截图 |
| 2026-08-21 | fix | 第四轮定点回修 | 面板 dark tint 调至 0.72、TextEditor top=17；设置 contentPane 改为 top=19/bottom=13 且侧栏选中背景改为先撑满后绘制并固定 32pt 行高；历史 searchHeader/row padding 与 metadataCard 填满 72 高度；菜单栏改为 `button.bounds -> convert(to:nil) -> convertToScreen`，脚本新增 rect 非负、82x60、三态 hash 不同硬校验 |
| 2026-08-21 | verify | 第四轮复跑（待 Codex） | 已执行 `git diff --check`、`swift test`、`swift build`、`build-app`、`capture`；当前仅提供新证据，不声明最终通过 |
| 2026-08-21 | fix | 菜单栏证据链路定向修复 | 按 Codex 探测结果移除 AppDelegate 内 rect 推断；脚本改为按 app PID 直接查询 WindowServer（`optionAll+excludeDesktopElements`，`layer=25` / `Item-0` 优先，回退几何窗口）；截图坐标直接使用 Quartz bounds，不再使用 accessibilityFrame/convertToScreen/clamp/固定 82x60 |
| 2026-08-21 | verify | 菜单栏定向验证后全量复跑（待 Codex） | menubar-only 与全量 capture 均通过；meta 记录 `pid/window_id/layer/name/bounds/appearance/pixel/hash`，三态 hash 互异；本轮仍待 Codex 复验，不宣称通过 |
| 2026-08-22 | accept | T16 最终验收通过 | 5/5 单元测试、Debug/Release 构建、打包、签名和 diff 检查通过；冻结状态、菜单栏三态及真实交互证据完成复验，用户确认验收完成 |

## 技术决策

| 决策 | 采用方案 | 未采用方案 | 原因 |
| --- | --- | --- | --- |
| 任务管理 | 单个 T16，内部 5 个顺序工作包 | 连续启动 T16–T20 | 项目要求一个任务验收、确认、提交后才能进入下一任务 |
| 菜单栏主符号 | `translate` | `sparkles.rectangle.stack` | 一级入口优先表达翻译；双结果属于二级语义 |
| 视觉基线 | 原生应用截图 + 几何和状态规则 | 对生成式 JPG 做整窗像素比较 | 毛玻璃、字体和 SF Symbols 会随系统环境变化 |
| 卡片实现 | 保持现有视图结构，局部增加完整卡片容器 | 重做窗口架构或引入完整设计系统 | 降低改动面，避免影响业务状态 |
| Git 操作 | Cursor 只实现和验证 | Cursor 自动提交或推送 | 项目要求用户确认验收后再提交 |

## 踩坑记录

| 问题 | 原因 | 解决方案 | 是否沉淀到知识库 |
| --- | --- | --- | --- |
| 菜单栏应用无法被当前界面工具捕获 | LSUIElement 没有普通可访问窗口 | 代码和构建先验收，菜单栏与浮动面板保留真机状态矩阵 | [ ] |
| 工作区在评审期间发生未提交变化 | T15 仍在修改 | 记录基线，禁止 reset/clean，验收时复查完整 diff | [ ] |
| 拖拽手柄被窗口背景拖动吞掉事件 | isMovableByWindowBackground=true 时，SwiftUI 透明视图默认 mouseDownCanMoveWindow=true | 手柄改为 AppKit 原生 NSView + NSViewRepresentable 桥接，override mouseDownCanMoveWindow=false | [x] |

## 知识发现

- [ ] **设计稿边界**：生成式概念稿适合表达层级和方向，不适合作为 macOS 原生材质的像素基线。
- [ ] **菜单栏验收**：状态项必须在浅色、深色和按下高亮三种状态下检查模板渲染。
- [ ] **动态布局验收**：可拖拽区域必须覆盖最小、默认和最大三个边界值。

## Spec-Code 偏差记录

| 偏差点 | Spec 预期 | 实际情况 | 处理方式 |
| --- | --- | --- | --- |
| 测试竞态 | 取消后旧任务不影响新状态 | 旧 CancellationError 可覆盖新测试 | 增加 testGeneration 代次令牌 |
| API Key 眼睛按钮 | 按钮在输入框边框内 | padding 导致按钮落在边框外 | 改为单一 HStack 圆角容器 |
| 历史设备名溢出 | 长名尾部省略 | fixedSize 拒绝压缩 | 移除 fixedSize，限制 maxWidth |
| 光标 push/pop 失配 | 悬停显示调整光标 | 隐藏后 isCursorPushed 残留 | 改用 NSCursor.set() |
| 文档多处不一致 | 16 项任务/translate 图标 | 15 项/sparkles.rectangle.stack | 逐项修正 docs/03/04/06/spec/tasks/log |
| 13.5 覆盖声明缺失 | 紧凑图标覆盖旧文案 | 旧 13.1 仍写"已复制"文字 | 13.5 增加覆盖优先说明 |
| 复制 checkmark 连续点击 | 每次复制反馈保持 1.5 秒 | try? 吞掉 CancellationError，旧任务立即清除新 checkmark | 改为 do/catch return |
| 手柄拖拽带动窗口移动 | 手柄拖拽只调节输入高度 | SwiftUI 透明 Rectangle 的 mouseDownCanMoveWindow 默认 true，被 isMovableByWindowBackground 吞掉 | 手柄改为 AppKit NSView（mouseDownCanMoveWindow=false） |

以上偏差均在审查和真机验收后修复（首轮 6 项 + 二次 1 项 + 用户复现 1 项），最终一致性已于 2026-08-22 验收通过。

## 实施验证结果（实现方自检）

| 验证命令 | 退出码 | 说明 |
| --- | --- | --- |
| `git diff --check` | 0 | 无空白错误（初次实施自检） |
| `swift build` | 0 | Debug 编译通过（初次实施自检） |
| `bash Scripts/build-app.sh` | 0 | Release 打包成功（初次实施自检） |
| `codesign --verify --deep --strict --verbose=2 build/LightTrans.app` | 0 | valid on disk（初次实施自检） |

### 回修后验证结果（实现方自检）

| 验证命令 | 退出码 | 说明 |
| --- | --- | --- |
| `git diff --check` | 0 | 无空白错误 |
| `swift build` | 0 | Debug 编译通过 |
| `bash Scripts/build-app.sh` | 0 | Release 打包成功 |
| `codesign --verify --deep --strict --verbose=2 build/LightTrans.app` | 0 | valid on disk, satisfies Designated Requirement |

> 以上为实现方（Cursor）自检结果，非最终验收。最终验收由 Codex 独立执行。

## Codex 独立验证结果

| 验证项 | 结果 | 证据 |
| --- | --- | --- |
| 完整 diff 与业务边界审查 | 通过 | 未修改翻译任务、存储格式、依赖和窗口尺寸；首轮、二次共发现 7 项问题，均已回修 |
| `git diff --check` | 通过 | 退出码 0 |
| `swift build` | 通过 | Debug 构建完成，退出码 0 |
| `bash Scripts/build-app.sh` | 通过 | Release 编译、应用组装和 ad-hoc 签名完成，退出码 0 |
| `codesign --verify --deep --strict --verbose=2 build/LightTrans.app` | 通过 | `valid on disk`，`satisfies its Designated Requirement`，退出码 0 |
| 真机 UI 状态矩阵 | 通过 | 19 个冻结窗口状态、菜单栏三态、真实输入高度拖拽、左键打开面板和右键真实菜单均完成验证 |

当前验收结论：静态、构建和真机 UI 验收均通过；用户已于 2026-08-22 确认完成 T16 验收。

### WP-3 返工验证结果（实现方自检）

| 验证命令 | 退出码 | 说明 |
| --- | --- | --- |
| `git diff --check` | 0 | 无空白错误 |
| `swift build` | 0 | Debug 编译通过 |
| `bash Scripts/build-app.sh` | 0 | Release 打包成功 |
| `codesign --verify --deep --strict --verbose=2 build/LightTrans.app` | 0 | valid on disk, satisfies Designated Requirement |

> WP-3 初次自检通过但 Codex 独立验收发现 3 项窗口尺寸/选中态阻塞问题，已回修。最终验证以回修后构建结果为准。

> WP-3 改动文件：DesignTokens.swift（新增）、TranslatePanelView.swift、SettingsView.swift、HistoryWindowView.swift、AppDelegate.swift、log.md、tasks.md

### WP-4 验证结果（Codex）

| 验证命令 | 退出码 | 说明 |
| --- | --- | --- |
| `git diff --check` | 0 | 无空白错误 |
| `swift test` | 0 | 新增 3 条输入高度测试全部通过 |
| `swift build` | 0 | Debug 构建通过 |
| `bash Scripts/build-app.sh` | 0 | Release 打包成功 |
| `codesign --verify --deep --strict --verbose=2 build/LightTrans.app` | 0 | valid on disk, satisfies its Designated Requirement |
| `bash Scripts/capture-ui-acceptance.sh` | 0 | 19 个冻结状态截图通过 frame/像素尺寸校验，并校验 `UI_ACCEPTANCE_ENV`（含 key/main/active）；菜单栏为真实 rect 实拍（dark/light/pressed）并输出 overlay 产物 |
| Release 字符串检查 | 0 | `strings <release-binary> | rg "ui-acceptance|UIAcceptance|menubar-state"` 无命中，Release 未暴露验收入口字符串 |

- 补充说明：
  - 菜单栏 pressed 高亮已完成补充验证，深色、浅色和按下三态 hash 互异。
  - 真实鼠标拖拽输入高度门禁已由 Codex 关闭。
  - 第四轮视觉像素对齐已完成复验，T16 最终验收通过。
