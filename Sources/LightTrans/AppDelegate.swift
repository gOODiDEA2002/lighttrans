import AppKit
import SwiftUI
import KeyboardShortcuts

// 面板显示时发出的通知，供面板内容据此聚焦输入框
extension Notification.Name {
    static let panelDidShow = Notification.Name("LightTrans.panelDidShow")
    // 历史窗口打开时发出，触发历史记录重新加载
    static let historyReload = Notification.Name("LightTrans.historyReload")
}

// 应用总管：状态栏图标、浮动面板、设置与历史窗口、全局快捷键监听的总入口
// 已实现：状态栏、浮动面板与快捷键、历史窗口；设置窗口在 T8 实现
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var panelViewModel: PanelViewModel!
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var shortcutTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        startShortcutListener()
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

    // 创建浮动面板与其内容视图
    private func setupPanel() {
        panelViewModel = PanelViewModel()
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600))
        panel.contentView = NSHostingView(rootView: TranslatePanelView(viewModel: panelViewModel))
    }

    // 启动 Option+T 全局快捷键监听（详细设计 3.2，铁律 L-3）
    private func startShortcutListener() {
        shortcutTask = Task { @MainActor in
            for await _ in KeyboardShortcuts.events(.keyDown, for: .togglePanel) {
                togglePanel()
            }
        }
    }

    // 呼出/隐藏翻译面板：已显示则隐藏，否则定位后显示并聚焦输入框
    func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            // 通知面板内容聚焦输入框
            NotificationCenter.default.post(name: .panelDidShow, object: nil)
        }
    }

    // 定位到当前含鼠标的屏幕：水平居中、顶部向下 22%（详细设计 3.2）
    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let originX = visible.midX - size.width / 2
        let originY = visible.maxY - visible.height * 0.22 - size.height
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    // 打开设置窗口：LSUIElement 应用需先激活本应用，窗口方能获焦可输入（铁律 L-2）
    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.preferredContentSize]   // 窗口按内容自适应尺寸
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "设置"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // 打开历史窗口：LSUIElement 应用需先激活本应用，窗口方能获焦（铁律 L-2）
    @objc private func openHistory() {
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "历史记录"
            window.contentView = NSHostingView(rootView: HistoryWindowView())
            window.center()
            window.isReleasedWhenClosed = false
            historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
        // 每次打开都刷新一次数据
        NotificationCenter.default.post(name: .historyReload, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension KeyboardShortcuts.Name {
    // 呼出翻译面板的全局快捷键，默认 Option+T（铁律 L-3）
    static let togglePanel = Self("togglePanel", default: .init(.t, modifiers: [.option]))
}
