# T16 UI 视觉一致性与交互精修

> 状态：accepted
> 创建日期：2026-08-21
> 复杂度：复杂
> 权威来源：`docs/03-detailed-design.md`、`docs/06-ui-optimization-proposal.md`、本 Spec

## 1. 背景与目标

T12–T14 已完成验收并提交。T15 的改动处于未提交状态被保留在工作区。T16 为用户明确授权的后续视觉一致性精修任务。当前实现满足主要尺寸与功能要求，但设计稿、文字规格和代码仍存在差异：部分设计图已经过时，卡片视觉层级没有完整实现，设置连通性测试缺少界面取消入口，历史搜索没有按设计归属左侧列表。

本次变更在不修改翻译、存储和窗口生命周期的前提下完成以下目标：

1. 建立可执行、可验收的 UI 视觉基线。
2. 统一三个窗口的卡片、状态和复制操作语言。
3. 补齐设置测试取消、历史搜索清空和拖拽手柄无障碍操作。
4. 保持现有窗口尺寸、数据格式、任务生命周期和快捷键行为不变。
5. 通过构建、Release 打包、签名和真机状态矩阵验收。

## 2. 代码现状

### 2.1 相关入口与调用关系

- `Sources/LightTrans/AppDelegate.swift`：创建菜单栏状态项、翻译面板、设置窗口和历史窗口。
- `Sources/LightTrans/UI/FloatingPanel.swift`：管理 560 × 600 pt 浮动面板、Esc 隐藏和失焦隐藏。
- `Sources/LightTrans/UI/TranslatePanelView.swift`：负责输入区、动态高度手柄、操作栏、双结果区和底部入口。
- `Sources/LightTrans/UI/SettingsView.swift`：负责 4 项侧边栏分页、接口配置、双模板、快捷键和历史设置。
- `Sources/LightTrans/UI/HistoryWindowView.swift`：负责搜索、记录列表、选中状态、元数据和正文详情。
- `Sources/LightTrans/UI/PanelViewModel.swift`：负责双路翻译状态和复制动作；本次不得修改其任务语义。

### 2.2 已确认事实

1. 翻译面板固定为 560 × 600 pt；输入高度范围为 70–240 pt，默认 100 pt。当前垂直预算公式已经写入 `docs/06-ui-optimization-proposal.md`。
2. `TranslatePanelView.ResultSection` 当前仅给正文区域绘制圆角背景，标题、状态和复制按钮不在同一张视觉卡片内。
3. `SettingsView.runTestConnection()` 已支持任务取消，但测试中按钮被禁用，界面没有取消入口。
4. `HistoryWindowView.toolbar` 当前横跨整个窗口；设计要求搜索属于左侧列表，并提供一键清空。
5. 历史筛选和选中逻辑已经使用 `filtered`，长设备名和模型名已经支持尾部截断及悬浮提示。
6. 当前工作区包含未提交的 T15 改动。实现人员不得执行 `git reset`、`git checkout --`、`git clean` 或其他覆盖现有改动的操作。

### 2.3 硬约束

1. 不修改窗口尺寸：面板 560 × 600 pt，设置 520 × 450 pt，历史初始 680 × 480 pt。
2. 不修改 `PanelViewModel` 的双路任务、generation、停止和历史追加语义。
3. 不修改 `ConfigStore`、`HistoryStore`、Keychain 数据格式或 iCloud 同步规则。
4. 不引入第三方依赖，不创建 Xcode 工程。
5. 不删除或覆盖当前未提交改动。
6. 不执行安装、Git commit、push、rebase 或分支切换。
7. 设计稿只用于表达布局和层级；真实验收以 macOS 原生渲染为准，不要求毛玻璃像素级一致。

## 3. 功能与视觉要求

### 3.1 设计基线

- 将 `docs/06-ui-optimization-proposal.md` 升级为 v4.0，状态改为「实施中，待验收」。
- 明确现有 JPG 为概念稿，不作为像素级验收基线。
- 新增 `docs/assets/README.md`，列出当前权威概念稿、历史稿和菜单栏候选稿。旧图不删除。
- 补充跨窗口视觉规则：外层卡片、标题栏、分隔线、正文区、状态色和复制反馈。
- 菜单栏主符号采用 `translate`；`sparkles.rectangle.stack` 作为已评估但未采用的候选方案。原因是一级入口优先表达「翻译」，双结果结构属于二级语义。

### 3.2 翻译面板

- 保留现有输入高度算法和 600 pt 总高度预算。
- 操作栏增加低对比度圆角容器，不改变 28 pt 总高度。
- 每个结果区改为完整卡片：标题、局部状态、复制操作、分隔线和正文属于同一个圆角容器。
- 复制按钮优先采用紧凑方形图标按钮，复制后原位切换绿色 `checkmark`，保留 tooltip 和无障碍标签。
- 输入提示文案统一为「输入待翻译文字，按 ⌘↩ 开始」。
- 拖拽手柄增加无障碍标签、当前高度值和可调整动作；调整步长 10 pt，仍限制在 70–240 pt。
- 不改变生成中「停止」、双路局部状态、Esc 隐藏和底部入口行为。

### 3.3 设置窗口

- 测试中按钮切换为「取消测试」且保持可点击；取消后回到 idle，不写历史。
- 测试成功、失败信息放在操作按钮下方，允许两行显示，避免横向挤压。
- 耗时文案使用「当前配置连接成功（185 ms）」格式。
- API Key 眼睛按钮放入输入框尾部视觉区域，只保留显示/隐藏操作。
- 直译和转写模板各自使用完整卡片容器，保留 110 pt 编辑区和占位符徽章。
- 不修改配置持久化、Keychain、开机启动和快捷键记录逻辑。

### 3.4 历史窗口

- 保留 iCloud 待下载提示；搜索区域移动到左侧列表顶部。
- 搜索区域包含搜索图标、输入框、非空时的清空按钮、匹配数量和刷新按钮。
- 列表项固定为两层信息：第一层为状态点、原文摘要和时间；第二层为首选译文摘要和设备名。
- 首选译文摘要按 `literalOutput`、`output`、`rewriteOutput` 顺序取第一个非空值；没有输出时显示「暂无译文」。
- 详情中的原文、直译、转写改为完整卡片结构，复制行为保持不变。
- 空状态区分「暂无历史记录」「无匹配记录」「选择左侧记录查看详情」。
- 不修改筛选字段、选中保持规则和历史数据读取逻辑。

### 3.5 菜单栏图标

- 使用 `translate`，配置 `NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)`。
- 设置 `isTemplate = true`；保留 `character.bubble` 回退。
- 保持左键呼出面板、右键菜单行为不变。

## 4. 不在本次范围

- 翻译服务协议、Prompt 内容、模型配置语义。
- 历史记录删除、导出、排序或分页。
- 新增主题系统、自定义字体、自定义矢量图标或动画框架。
- 重做窗口架构、改用 `NavigationSplitView` 或引入完整设计系统。
- 自动安装到 `/Applications`。

## 5. 数据与接口变更

无数据结构、持久化格式、网络接口或 API 契约变更。

## 6. 影响范围

预计修改：

- `Sources/LightTrans/AppDelegate.swift`
- `Sources/LightTrans/UI/TranslatePanelView.swift`
- `Sources/LightTrans/UI/SettingsView.swift`
- `Sources/LightTrans/UI/HistoryWindowView.swift`
- `docs/03-detailed-design.md`
- `docs/04-implementation-plan.md`
- `docs/06-ui-optimization-proposal.md`
- `docs/assets/README.md`
- `docs/changes/ui-visual-consistency/tasks.md`
- `docs/changes/ui-visual-consistency/log.md`

允许在确有三处以上复用且不扩大状态管理时新增一个小型 UI 组件文件；默认优先局部实现。

## 7. 风险与防护

| 风险 | 影响 | 防护措施 |
| --- | --- | --- |
| 完整卡片增加内边距 | 最大输入高度时结果正文过小 | 保持结果区总高度不变，标题栏控制在 30 pt 左右，正文继续滚动 |
| 搜索栏移动改变选中状态 | 旧详情残留或选择丢失 | 保留 `syncSelectionAfterFilter()` 和 `filtered` 查找规则 |
| 测试取消产生迟到结果 | 取消后状态被旧任务覆盖 | 取消任务后检查 `Task.isCancelled`，显式恢复 idle |
| API Key 眼睛按钮遮挡文本 | 输入末尾不可见或点击困难 | 为输入字段预留尾部空间，保持明确 hit target |
| 菜单栏图标在旧系统不可用 | 状态项无图标 | 保留 `character.bubble` 回退 |
| 工作区存在未提交改动 | 用户改动丢失 | 禁止重置、清理和覆盖；修改前后检查 `git diff` |

## 8. 待澄清

无。用户已授权按本方案编写排工并交由 Cursor 实现；菜单栏图标采用上轮评审推荐的 `translate`。

## 9. 验收标准

- [x] 文档、设计说明和代码使用同一菜单栏符号与布局规则。
- [x] 面板在输入高度 70、100、240 pt 时均无裁切，两个结果区等高且可滚动。
- [x] 面板 idle、streaming、done、partial-fail、stopped 状态层级清晰。
- [x] 测试连接可在界面中取消，成功和长错误文案不横向挤压。
- [x] 历史搜索位于左侧列表，支持清空、计数、刷新和正确空状态。
- [x] 三个窗口的卡片、复制和状态视觉语言一致。
- [x] 拖拽手柄和状态点具备必要的 VoiceOver 语义。
- [x] `git diff --check`、`swift build`、Release 打包和严格签名校验通过。
- [x] 不存在安装、提交、推送、依赖或数据格式变更。
