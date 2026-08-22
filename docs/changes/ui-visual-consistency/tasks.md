# 任务拆分——T16 UI 视觉一致性与交互精修

> 本次按项目规则作为一个 T16 交付；以下为同一任务内部的顺序工作包，不单独提交。
> Cursor 负责实现，Codex 负责独立验收。验收通过并经用户确认前不得提交。

## 前置条件

- [x] Spec 已确认：用户已要求编写排工并安排 Cursor 实现。
- [x] 已读取当前实现和 UI 方案。
- [x] 已确认工作区存在未提交的 T15 改动，必须保留。
- [x] Cursor CLI 已安装并登录。
- [x] 用户已于 2026-08-22 确认 T16 验收完成；本文件随 T16 提交。

## 工作包 A：冻结视觉基线

- **目标**：让文档、设计资产说明和代码使用同一组决策。
- **涉及文件**：
  - `docs/06-ui-optimization-proposal.md`
  - `docs/03-detailed-design.md`
  - `docs/04-implementation-plan.md`
  - `docs/assets/README.md`
  - `docs/changes/ui-visual-consistency/log.md`
- **实施内容**：
  1. UI 方案升级为 v4.0，状态设为「实施中，待验收」。
  2. 明确概念稿与真实验收截图的边界。
  3. 增加跨窗口卡片、状态、复制按钮和语义色规范。
  4. 记录 `translate` 为菜单栏最终设计，`sparkles.rectangle.stack` 为候选稿。
  5. 在实施计划中增加 T16，验收结果保持「待验收」。
- **验收标准**：全文搜索不存在相互冲突的菜单栏主符号或已废弃局部重试规则。
- **验证命令**：`rg -n "translate|sparkles.rectangle.stack|局部重试|状态：" docs`
- [x] 完成

## 工作包 B：翻译面板视觉精修

- **目标**：完整实现原设计中的卡片层级，同时保留 T15 动态高度。
- **涉及文件**：
  - `Sources/LightTrans/UI/TranslatePanelView.swift`
  - 必要时新增一个小型共享 UI 组件文件
- **关键位置**：
  - `TranslatePanelView.actionRow`
  - `TranslatePanelView.resizeHandle`
  - `ResultSection.body`
  - `ResultSection.copyButton`
- **实施内容**：
  1. 操作栏增加轻量圆角容器。
  2. 结果标题、状态、复制和正文纳入同一张圆角卡片。
  3. 复制按钮改为紧凑图标反馈，补全 tooltip 和无障碍标签。
  4. 拖拽手柄增加无障碍可调整动作。
  5. 统一输入提示文案。
- **验收标准**：70/100/240 pt 三个输入高度下均无静态溢出；结果正文保持独立滚动。
- **验证命令**：`swift build`
- [x] 完成

## 工作包 C：设置窗口交互与卡片精修

- **目标**：补齐测试取消，并改善 380 pt 内容区的视觉密度。
- **涉及文件**：
  - `Sources/LightTrans/UI/SettingsView.swift`
- **关键位置**：
  - `apiConfigView`
  - `testStatusView`
  - `runTestConnection()`
  - `templatesConfigView`
- **实施内容**：
  1. 测试中显示「取消测试」并可取消当前任务。
  2. 测试状态移动到按钮下方，成功耗时使用 `185 ms` 格式。
  3. API Key 显示按钮并入输入框尾部视觉区域。
  4. 双模板使用完整卡片容器。
- **验收标准**：测试取消后不显示迟到结果；长错误最多两行且不挤压按钮；520 × 450 pt 无裁切。
- **验证命令**：`swift build`
- [x] 完成

## 工作包 D：历史窗口扫读与搜索精修

- **目标**：恢复左栏搜索归属并提升列表扫读效率。
- **涉及文件**：
  - `Sources/LightTrans/UI/HistoryWindowView.swift`
- **关键位置**：
  - `body`
  - `toolbar` 或替代的 `searchHeader`
  - `listView`
  - `detailView`
  - `DetailCard.body`
- **实施内容**：
  1. 搜索、清空、数量和刷新放入左侧头部。
  2. 列表改为两层内容结构，不增加显著行高。
  3. 详情正文改为完整卡片结构。
  4. 区分无历史、无匹配和未选择三种空状态。
  5. 保持筛选、刷新和选中规则不变。
- **验收标准**：搜索后不存在旧详情；清空恢复全量并保持合理选中；长设备和模型不溢出。
- **验证命令**：`swift build`
- [x] 完成

## 工作包 E：实施记录与自检

- **目标**：为 Codex 验收提供完整证据。
- **涉及文件**：
  - `docs/changes/ui-visual-consistency/tasks.md`
  - `docs/changes/ui-visual-consistency/log.md`
- **实施内容**：
  1. 勾选实际完成的工作包。
  2. 记录任何 Spec-Code 偏差；出现偏差时先更新 Spec。
  3. 汇总修改文件和验证结果。
- **验证命令**：
  - `git diff --check`
  - `swift build`
  - `bash Scripts/build-app.sh`
  - `codesign --verify --deep --strict --verbose=2 build/LightTrans.app`
- **禁止操作**：安装、Git commit、push、rebase、reset、clean。
- [x] 完成

## Codex 独立验收清单

### 静态与构建

- [x] 检查完整 diff 和文件范围。
- [x] 检查未覆盖或误改的业务逻辑。
- [x] 执行 `git diff --check`。
- [x] 执行 `swift build`。
- [x] 执行 Release 打包和严格签名校验。

### UI 状态矩阵

- [x] 面板：idle、streaming、done、partial-fail、stopped。
- [x] 输入高度：70、100、240 pt；双击复位 100 pt。
- [x] 设置：testing、cancel、success、长错误、模板有效/无效。
- [x] 历史：正常列表、搜索有结果、无匹配、无历史、长设备名和模型名。
- [x] 菜单栏：浅色、深色、点击高亮、左键和右键。
- [x] 键盘与 VoiceOver：主要按钮、搜索清空、拖拽高度调整。

### Codex 独立验收结论

- 代码审查、文档一致性、5/5 单元测试、Debug/Release 构建、应用打包和严格签名校验已通过。
- 19 个冻结窗口状态、菜单栏三态、真实输入高度拖拽、左键打开面板和右键真实菜单均已完成验证。
- 用户已于 2026-08-22 确认 T16 验收完成，满足提交条件。

## WP-3：按 v5 token 表全量视觉返工

- **目标**：将三窗口视觉全部对齐 v5 唯一基准图和 token 表，消除 magic number。
- **涉及文件**：
  - `Sources/LightTrans/UI/DesignTokens.swift`（新增）
  - `Sources/LightTrans/UI/TranslatePanelView.swift`
  - `Sources/LightTrans/UI/SettingsView.swift`
  - `Sources/LightTrans/UI/HistoryWindowView.swift`
  - `Sources/LightTrans/AppDelegate.swift`
  - `docs/changes/ui-visual-consistency/log.md`
  - `docs/changes/ui-visual-consistency/tasks.md`
- **实施内容**：
  1. 新增 `DesignTokens.swift`，收敛全部 v5 尺寸、字号、圆角、间距、语义色为 `V5` 枚举常量。
  2. TranslatePanelView：全部 magic number 替换为 V5 token；局部失败正文区增加引导文案。
  3. SettingsView：全部 magic number 替换为 V5 token；验证侧栏 139+1=140 和右侧 380 分栏。
  4. HistoryWindowView：HSplitView 改为 HStack 固定分栏（269+1=270 左、410+ 右）；搜索头部改为两行结构（76pt）；列表行高对齐 64pt；详情复制按钮改为带「复制」文字；元数据和正文卡片统一 v5 cardFill/cardBorder/cardCornerRadius；语义色使用 V5 常量。
  5. AppDelegate：窗口尺寸改为引用 V5 token 常量。
- **验收标准**：git diff --check / swift build / Release 打包 / 严格签名全部通过；真机截图由 Codex 验收。
- [x] 通过。首次验收发现的面板 frame、历史 frame 和列表选中态问题均已修复，并纳入后续冻结状态与真机验证。

## 变更摘要

- 修改源码文件：5（DesignTokens.swift 新增、AppDelegate.swift、TranslatePanelView.swift、SettingsView.swift、HistoryWindowView.swift）
- 修改文档文件：2（log.md、tasks.md）
- Spec-Plan 偏差：Codex 审查共发现 7 项问题（首轮 6 项 + 二次 1 项 + 真机 1 项），已全部回修（详见 log.md）。WP-3 为用户确认 v5 基准后的全量返工。
- 遗留问题：无。

## WP-4：Debug UI 验收态与截图脚本

- **目标**：按 v5 基线补齐全量 UI 冻结态启动入口、截图脚本和输入高度纯函数测试。
- **涉及文件**：
  - `Sources/LightTrans/UI/UIAcceptanceState.swift`（新增）
  - `Sources/LightTrans/AppDelegate.swift`
  - `Sources/LightTrans/UI/TranslatePanelView.swift`
  - `Sources/LightTrans/UI/SettingsView.swift`
  - `Sources/LightTrans/UI/HistoryWindowView.swift`
  - `Sources/LightTrans/UI/PanelInputHeightMath.swift`（新增）
  - `Tests/LightTransTests/PanelInputHeightMathTests.swift`（新增）
  - `Package.swift`
  - `Scripts/capture-ui-acceptance.sh`（新增）
- **实施内容**：
  1. 新增 Debug-only `UIAcceptanceState` 与 `--ui-acceptance-state` 参数，覆盖面板/设置/历史全部要求状态。
  2. 复用生产视图渲染冻结窗口：面板通过 `PanelViewModel` 预置状态；设置与历史注入快照数据；冻结态不触发真实网络请求。
  3. 验收窗口在 DEBUG 路径强制 `NSAppearance(named: .darkAqua)`，并输出 `UI_ACCEPTANCE_ENV` 日志；脚本校验 `appearance=NSAppearanceNameDarkAqua` 与 `scale=2.0`。
  4. 面板/设置/历史验收文案改为对齐 `docs/assets/v5`，`panel-idle` 改为非空输入并显示 `82 字符`。
  5. streaming 停止按钮改为确定性红色警示样式（红字/红图标/淡红背景/红描边），保留 `⌘↩` 行为。
  6. 输入区与模板 `TextEditor` 隐藏滚动指示器并去除右侧滚动条区域。
  7. 新增 `capture-ui-acceptance.sh`，按状态启动 Debug app、按 PID 捕获并校验 frame 与截图尺寸，输出到 `build/ui-acceptance`；同时产出 `state-mapping.txt`。
  8. 菜单栏证据补充：Debug 路径输出真实 `NSStatusItem` 屏幕 rect；脚本使用系统 `screencapture -R` 采集 dark/light，pressed 走 CGEvent `mouseDown` 截图并补充 `manual-required` 门禁说明。
  9. 抽离输入高度纯函数 `PanelInputHeightMath` 并新增 Swift Test，覆盖 70/100/240、向下增大、向上减小。
  10. 脚本新增 50% overlay 生成，输出到 `build/ui-acceptance/overlays/`（8 张基准图）。
- **验收结果**：
  - `git diff --check`：通过
  - `swift test`：通过（3/3）
  - `swift build`：通过
  - `bash Scripts/build-app.sh`：通过
  - `codesign --verify --deep --strict --verbose=2 build/LightTrans.app`：通过
  - `bash Scripts/capture-ui-acceptance.sh`：通过（19 个窗口状态全部产图 + 菜单栏 dark/light/pressed 实拍 + overlays）
- **最终验收**：
  - [x] 菜单栏 pressed 高亮截图完成补证据，深色、浅色和按下三态 hash 互异。
  - [x] 真实鼠标拖拽输入高度行为：Codex 已验证 `100→240`、`100→70`，窗口 frame 始终 `(1000,221,560,600)`，原点 delta=`(0,0)`，P1 已关闭。
  - [x] 第四轮视觉像素对齐复验通过，用户于 2026-08-22 确认 T16 验收完成。

## WP-4 第四轮定点回修

- **实施内容（仅定点）**：
  1. 面板深色 tint `0.34 -> 0.72`；输入正文 top padding `14 -> 17`，其余输入区对齐参数不改。
  2. 设置页 contentPane 改为 `left/right=16, top=19, bottom=13`；侧栏每项固定高 32，selected 背景改为撑满行宽后绘制；外边距改为 `horizontal=10, top=16, bottom=10`。
  3. 历史页：searchHeader horizontal `11 -> 10`；historyRow horizontal `12 -> 17`；metadataCard 在背景绘制前填满外层高度。
  4. 菜单栏：AppDelegate 的 DEBUG menubar 模式仅创建真实状态项并输出 ready；坐标发现下沉到脚本（按 PID 查询 WindowServer，`layer=25` / `Item-0` 优先）；按查询到的 bounds 直接截图，像素校验改为 `2*w x 2*h`（本机 82x48）；pressed 用 Quartz 坐标中心发送 CGEvent；三态 hash 必须互异。
- **状态**：已完成代码与命令复跑，Codex 复验和用户验收均通过。
