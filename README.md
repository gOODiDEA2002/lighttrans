# 轻译（LightTrans）

macOS 菜单栏翻译小工具：全局快捷键呼出浮动面板，输入文字后按预设提示词模板交给大模型翻译，流式显示译文。仅面向个人本机使用。

## 项目状态

设计阶段已完成，尚未编码。设计文档见 docs/ 目录，编码按 docs/04-implementation-plan.md 的任务清单执行。

## 功能概览（第一期）

- 菜单栏常驻，不占用 Dock；默认快捷键 Option+T 呼出翻译面板。
- 面板内输入文字，Cmd+Return 翻译，译文流式显示，一键复制。
- 大模型接口可配置：接口地址、API Key、模型名、提示词模板、最大输出 token 均可在设置中修改，兼容一切 OpenAI 格式的服务（OpenAI、DeepSeek、通义、本地 Ollama 等）。
- API Key 存入系统钥匙串；支持开机自启。
- 每次翻译的原始输入与输出自动保存为历史记录，经 iCloud 云盘在多台电脑间同步，历史窗口按时间合并显示全部设备的记录（无需苹果开发者账号，采用"每设备一个只追加文件"的无冲突结构）。

## 技术要点

- Swift + SwiftUI，AppKit 管理状态栏与浮动面板；Swift Package Manager 工程。
- 全局快捷键依赖 sindresorhus/KeyboardShortcuts。
- 最低部署目标 macOS 14，开发与运行环境 macOS 15.7.4。

## 文档索引

| 文档 | 内容 |
| --- | --- |
| docs/01-requirements.md | 需求：功能清单、非功能指标、分期范围、验收口径 |
| docs/02-system-design.md | 系统设计：架构、技术决策、数据流、铁律清单与待验证假设 |
| docs/03-detailed-design.md | 详细设计：工程结构、各模块接口、界面规格、接口协议、错误映射、打包 |
| docs/04-implementation-plan.md | 实施计划：编码任务清单 T1–T10 与逐项验收标准 |
| docs/05-kickoff-prompt.md | 编码会话开工提示词模板与派活流程 |

## 构建与安装

待编码完成后补充（见实施计划 T9）。
