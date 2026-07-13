import AppKit
import KeyboardShortcuts

// 应用总管：状态栏图标、浮动面板、设置与历史窗口、全局快捷键监听的总入口
// T1 阶段仅建立骨架，各项职责从 T2 起按详细设计第 3 节逐步实现
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 后续任务填充：创建状态栏图标、面板、快捷键监听等
    }
}

extension KeyboardShortcuts.Name {
    // 呼出翻译面板的全局快捷键，默认 Option+T（铁律 L-3）
    static let togglePanel = Self("togglePanel", default: .init(.t, modifiers: [.option]))
}
