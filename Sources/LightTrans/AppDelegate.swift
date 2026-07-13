import AppKit
import SwiftUI
import KeyboardShortcuts

// 面板显示时发出的通知，供面板内容据此聚焦输入框
extension Notification.Name {
    static let panelDidShow = Notification.Name("LightTrans.panelDidShow")
}

// 应用总管：状态栏图标、浮动面板、设置与历史窗口、全局快捷键监听的总入口
// T5 阶段实现浮动面板与全局快捷键；设置、历史窗口从 T7 起按详细设计逐步实现
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
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

    // 创建浮动面板（内容暂为 A-1 验证用的临时输入视图，T6 替换为 TranslatePanelView）
    private func setupPanel() {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 220))
        panel.contentView = NSHostingView(rootView: PanelProbeView())
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

// T5 临时面板内容：用于验证假设 A-1（中文输入法含候选窗可正常输入）
// T6 将整体替换为 TranslatePanelView
private struct PanelProbeView: View {
    @FocusState private var focused: Bool
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A-1 验证：请用中文输入法输入（观察候选窗是否正常）")
                .font(.callout)
                .foregroundColor(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
                .focused($focused)
            Text("字数：\(text.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 560, height: 220)
        .onAppear { focusInput() }
        // 每次面板呼出都重新聚焦输入框
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            focusInput()
        }
    }

    private func focusInput() {
        DispatchQueue.main.async { focused = true }
    }
}
