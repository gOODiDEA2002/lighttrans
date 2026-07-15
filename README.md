# 轻译（LightTrans）

macOS 菜单栏翻译小工具：全局快捷键呼出浮动面板，输入文字后按预设提示词模板交给大模型翻译，流式显示译文。仅面向个人本机使用。

## 项目状态

第一期（FR-1 至 FR-11）已完成并通过验收。设计文档见 docs/ 目录，验收记录见 docs/04-implementation-plan.md 第 2 节。

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

环境要求：macOS 14 及以上；已安装 Xcode 或 Swift 工具链（Swift 5.9+）。

推荐直接执行一键脚本。脚本会构建 release 版本、安装或更新 `/Applications/LightTrans.app`，并重新启动应用；已有设置、API Key 和历史记录不会被删除。

```bash
bash Scripts/install-app.sh
```

如果 `/Applications` 需要管理员权限，脚本会在文件替换阶段请求系统密码。需要安装到其他目录时，可设置 `LIGHTTRANS_INSTALL_DIR`：

```bash
LIGHTTRANS_INSTALL_DIR="$HOME/Applications" bash Scripts/install-app.sh
```

只构建、不安装时执行：

```bash
bash Scripts/build-app.sh
```

产物位于 `build/LightTrans.app`，采用 ad-hoc 本地签名。

应用图标的源文件为 `Resources/AppIcon.png`。修改源图后，先重新生成 `.icns`，再构建：

```bash
bash Scripts/generate-app-icon.sh
```

首次启动仅在菜单栏出现图标（气泡样式），不出现在 Dock。

仅本机使用，无需苹果开发者签名与公证；采用 ad-hoc 本地签名。

## 使用

- 按 `Option+T`（或左键点菜单栏图标）呼出翻译面板；再按一次、按 `Esc`、或点击面板外部即隐藏。
- 输入文字，按 `Cmd+Return` 翻译，译文流式显示；翻译中按钮变"停止"，可中断。
- 点结果区"复制"按钮一键复制译文。
- 右键菜单栏图标可打开"历史记录…"与"设置…"，或退出。

## 配置

首次使用需在"设置"中填写接口信息（右键图标 → 设置…）：

- 接口地址（Base URL）、模型名、API Key（存入系统钥匙串）。
- 提示词模板：用 `{{text}}` 表示待翻译的原文；未包含占位符时，原文会追加到模板末尾。
- 最大输出 token（100–8000）：限制单次输出，防止误贴超长文本产生意外费用。
- 全局快捷键：可重新录制。
- 开机自启开关（应用需位于 /Applications）。
- 历史记录开关与存储位置显示。

兼容一切 OpenAI 格式的 chat/completions 接口（OpenAI、DeepSeek、通义、本地 Ollama 等），换厂商只需改设置。

## 在第二台 Mac 上安装（用于多设备同步）

前提：第二台 Mac 登录**同一个 Apple ID** 且已开启 **iCloud 云盘**，否则历史文件不会互相同步。

本应用采用 ad-hoc 本地签名，直接拷到别的电脑会被 macOS 拦截，二选一处理：

- 方式 A（推荐）：在第二台 Mac 上从源码构建（需已装 Swift 工具链），会自动在本机重新签名：

  ```bash
  cd mac-translator
  bash Scripts/install-app.sh
  ```

- 方式 B：把打好的 `LightTrans.app` 拷过去（隔空投送/U 盘/网络），在第二台 Mac 上去隔离标记并重新签名：

  ```bash
  xattr -dr com.apple.quarantine /Applications/LightTrans.app
  codesign --force --deep --sign - /Applications/LightTrans.app
  open /Applications/LightTrans.app
  ```

  若仍打不开，在访达中右键 App → 打开，弹窗中点"打开"放行一次。

装好后在第二台 Mac 的"设置"中同样填写接口地址、模型名、API Key（钥匙串每台机器独立）。每台电脑自动使用各自独立的历史文件（文件名后缀为各机器首次启动生成的设备标识），互不冲突；翻译后等 iCloud 同步（通常数秒至数分钟），任一台的历史窗口即可看到两台设备合并的记录。

## 历史记录

- 每次翻译结束（完成、手动停止、失败）追加一条记录，含原始输入、译文、时间、设备名、模型名、结束状态。
- 记录存于 iCloud 云盘 `LightTrans/history/history-{设备标识}.jsonl`，由系统在多台电脑间同步；每台设备只写自己的文件，无同步冲突。未开启 iCloud 云盘的电脑自动退化为仅存本机（`~/Library/Application Support/LightTrans/history/`）。
- 历史窗口按时间倒序合并显示全部设备记录，支持关键字过滤与复制。
