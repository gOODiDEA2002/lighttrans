import AppKit
import KeyboardShortcuts

// 应用总管：状态栏图标、浮动面板、设置与历史窗口、全局快捷键监听的总入口
// T2 阶段实现状态栏图标与右键菜单；面板、设置、历史窗口从 T5 起按详细设计逐步实现
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    // 创建状态栏图标：左键呼出面板，右键弹出菜单
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "轻译")
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        // 同时响应左右键抬起事件，在处理函数中按事件类型分流
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu(from: sender)
        } else {
            togglePanel()
        }
    }

    // 右键菜单：历史记录、设置、退出
    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "历史记录…", action: #selector(openHistory), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "")
        for item in menu.items where item.action != nil {
            item.target = self
        }
        // 在按钮下方弹出菜单，不占用 statusItem.menu 以保留左键动作
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    // 呼出/隐藏翻译面板（T5 实现具体逻辑）
    func togglePanel() {
        // 后续任务填充
    }

    @objc private func openSettings() {
        // T8 实现设置窗口
    }

    @objc private func openHistory() {
        // T7 实现历史窗口
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension KeyboardShortcuts.Name {
    // 呼出翻译面板的全局快捷键，默认 Option+T（铁律 L-3）
    static let togglePanel = Self("togglePanel", default: .init(.t, modifiers: [.option]))
}
