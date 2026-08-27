# 设计资产清单

本目录以 `v5/` 作为当前 UI 实施与验收的唯一视觉基准。尺寸、间距、字号、颜色和状态规则以 `docs/changes/ui-visual-consistency/v5-baseline.md` 为准。

## v5 唯一基准

| 文件名 | 状态 |
| --- | --- |
| `v5/lighttrans_panel_idle.png` | 翻译面板空闲态 |
| `v5/lighttrans_panel_streaming.png` | 翻译面板生成中 |
| `v5/lighttrans_panel_done.png` | 翻译面板完成态 |
| `v5/lighttrans_panel_partial_fail.png` | 翻译面板局部失败态 |
| `v5/lighttrans_panel_stopped.png` | 翻译面板停止态 |
| `v5/lighttrans_settings_api.png` | 设置窗口接口配置页 |
| `v5/lighttrans_settings_templates.png` | 设置窗口提示词模板页 |
| `v5/lighttrans_history.png` | 历史记录窗口；2026-08-27 重新采集并移除个人设备名 |

这些 PNG 按 macOS 15.7.4、深色外观、2× backing scale 输出。它们用于视觉位置和层级比较；系统字体抗锯齿、SF Symbols 细节和毛玻璃采样仍以真实 AppKit 渲染为准。

## 历史概念稿

`archive/` 保存 v3.0–v4.0 的生成式概念稿。历史稿不再参与实现决策或像素验收；与 v5 冲突时一律以 v5 为准。

## 菜单栏图标

- 当前主符号：`translate`。
- 兼容回退：`character.bubble`。
- `lighttrans_menubar_icons_mockup.png` 仅保留候选方案对比，不是窗口视觉基准。
