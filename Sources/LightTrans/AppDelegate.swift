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
#if DEBUG
    private var uiAcceptanceWindow: NSWindow?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if let menubarCapture = UIMenubarAcceptanceState.parse(arguments: ProcessInfo.processInfo.arguments) {
            fputs("UI_ACCEPTANCE_BOOT menubar=\(menubarCapture.rawValue)\n", stderr)
            launchMenubarAcceptance(state: menubarCapture)
            return
        }
        if let acceptanceState = UIAcceptanceState.parse(arguments: ProcessInfo.processInfo.arguments) {
            fputs("UI_ACCEPTANCE_BOOT state=\(acceptanceState.rawValue)\n", stderr)
            launchUIAcceptance(state: acceptanceState)
            return
        }
#endif
        setupStatusItem()
        setupPanel()
        startShortcutListener()
    }

    // 创建状态栏图标：左键呼出面板，右键弹出菜单（详细设计 13.4）
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        // 菜单栏主符号 translate，回退 character.bubble（详细设计 13.4、UI 方案 v4.0）
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let image = NSImage(systemSymbolName: "translate", accessibilityDescription: "轻译")?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        } else if let fallback = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "轻译")?.withSymbolConfiguration(config) {
            fallback.isTemplate = true
            button.image = fallback
        }

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

    // 创建浮动面板与其内容视图（详细设计 13.1 闭包依赖注入）
    // borderless + nonactivatingPanel 时 contentRect == frame，sizingOptions=[] 阻止 hosting view 撑大窗口
    private func setupPanel() {
        panelViewModel = PanelViewModel()
        let frameRect = NSRect(x: 0, y: 0, width: V5.Panel.width, height: V5.Panel.height)
        panel = FloatingPanel(contentRect: frameRect)
        let panelView = TranslatePanelView(
            viewModel: panelViewModel,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenHistory: { [weak self] in self?.openHistory() }
        )
        let hostingView = NSHostingView(rootView: panelView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(frameRect, display: false)
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
    // window.frame 严格 520x450 pt（v5 基准含标题栏），内容高度由 AppKit 反算
    @objc private func openSettings() {
        if settingsWindow == nil {
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            let targetFrame = NSRect(
                x: 0, y: 0,
                width: V5.Settings.width, height: V5.Settings.height
            )
            let contentRect = NSWindow.contentRect(forFrameRect: targetFrame, styleMask: styleMask)
            let window = NSWindow(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            let hostingView = NSHostingView(rootView: SettingsView())
            hostingView.sizingOptions = []
            window.contentView = hostingView
            window.setFrame(targetFrame, display: false)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // 打开历史窗口：LSUIElement 应用需先激活本应用，窗口方能获焦（铁律 L-2）
    // window.frame 严格 680x480 pt（v5 基准含标题栏），内容高度由 AppKit 反算
    @objc private func openHistory() {
        if historyWindow == nil {
            let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
            let targetFrame = NSRect(
                x: 0, y: 0,
                width: V5.History.width, height: V5.History.height
            )
            let contentRect = NSWindow.contentRect(forFrameRect: targetFrame, styleMask: styleMask)
            let window = NSWindow(
                contentRect: contentRect,
                styleMask: styleMask,
                backing: .buffered,
                defer: false
            )
            window.title = "历史记录"
            let hostingView = NSHostingView(rootView: HistoryWindowView())
            hostingView.sizingOptions = []
            window.contentView = hostingView
            // minSize 为完整 frame 尺寸；setFrame 在 sizingOptions=[] 之后确保 frame 精确
            window.minSize = NSSize(width: V5.History.width, height: V5.History.height)
            window.setFrame(targetFrame, display: false)
            window.center()
            window.isReleasedWhenClosed = false
            historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .historyReload, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

#if DEBUG
private extension AppDelegate {
    var acceptanceAppearance: NSAppearance {
        NSAppearance(named: .darkAqua) ?? NSAppearance(named: .aqua) ?? NSAppearance()
    }

    func launchUIAcceptance(state: UIAcceptanceState) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        switch state {
        case .panelIdle, .panelStreaming, .panelDone, .panelPartialFail, .panelStopped,
                .panelHeight70, .panelHeight100, .panelHeight240:
            launchPanelAcceptance(state: state)
        case .settingsAPIIdle, .settingsAPITesting, .settingsAPISuccess, .settingsAPILongError,
                .settingsTemplatesValid, .settingsTemplatesInvalid:
            launchSettingsAcceptance(state: state)
        case .historyNormal, .historySearchHit, .historyNoMatch, .historyNoRecords, .historyLongDeviceModel:
            launchHistoryAcceptance(state: state)
        }
    }

    func launchMenubarAcceptance(state: UIMenubarAcceptanceState) {
        setupStatusItem()
        guard let button = statusItem.button else {
            emitAcceptanceLog("UI_ACCEPTANCE_MENUBAR error=no-status-button")
            return
        }
        // DEBUG 菜单栏验收模式：阻断业务点击动作，避免 mouseUp 触发 togglePanel。
        // 不影响系统原生按压高亮渲染，仍可用于真实按下态截图。
        button.action = nil
        button.target = nil

        switch state {
        case .dark:
            button.appearance = NSAppearance(named: .darkAqua)
            button.highlight(false)
        case .light:
            button.appearance = NSAppearance(named: .aqua)
            button.highlight(false)
        case .pressed:
            button.appearance = NSAppearance(named: .darkAqua)
            button.highlight(false)
        }

        NSApp.activate(ignoringOtherApps: true)
        button.layoutSubtreeIfNeeded()
        let appearanceName = button.effectiveAppearance.name.rawValue
        emitAcceptanceLog("UI_ACCEPTANCE_MENUBAR_READY state=\(state.rawValue) appearance=\(appearanceName)")
    }

    func launchPanelAcceptance(state: UIAcceptanceState) {
        let frameRect = NSRect(x: 0, y: 0, width: V5.Panel.width, height: V5.Panel.height)
        panel = FloatingPanel(contentRect: frameRect)
        panelViewModel = UIAcceptancePanelScenario.makeViewModel(for: state)
        let panelView = TranslatePanelView(
            viewModel: panelViewModel,
            onOpenSettings: {},
            onOpenHistory: {},
            initialInputHeight: UIAcceptancePanelScenario.inputHeight(for: state),
            autoFocusInput: false,
            characterCountOverride: UIAcceptancePanelScenario.characterCount(for: state)
        )
        let hostingView = NSHostingView(rootView: panelView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.appearance = acceptanceAppearance
        panel.setFrame(frameRect, display: false)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        logAcceptanceEnvironment(window: panel, state: state.rawValue)
        NotificationCenter.default.post(name: .panelDidShow, object: nil)
    }

    func launchSettingsAcceptance(state: UIAcceptanceState) {
        let snapshot = UIAcceptanceSettingsSnapshot.make(for: state)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        let targetFrame = NSRect(x: 0, y: 0, width: V5.Settings.width, height: V5.Settings.height)
        let contentRect = NSWindow.contentRect(forFrameRect: targetFrame, styleMask: styleMask)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: SettingsView(uiAcceptanceSnapshot: snapshot))
        hostingView.sizingOptions = []
        window.title = "设置"
        window.contentView = hostingView
        window.appearance = acceptanceAppearance
        window.setFrame(targetFrame, display: false)
        window.center()
        window.isReleasedWhenClosed = false
        uiAcceptanceWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        waitForWindowActivation(window)
        logAcceptanceEnvironment(window: window, state: state.rawValue)
        emitAcceptanceEnvironmentSamples(window: window, state: state.rawValue, remaining: 24)
    }

    func launchHistoryAcceptance(state: UIAcceptanceState) {
        let snapshot = UIAcceptanceHistorySnapshot.make(for: state)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let targetFrame = NSRect(x: 0, y: 0, width: V5.History.width, height: V5.History.height)
        let contentRect = NSWindow.contentRect(forFrameRect: targetFrame, styleMask: styleMask)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: HistoryWindowView(uiAcceptanceSnapshot: snapshot))
        hostingView.sizingOptions = []
        window.title = "历史记录"
        window.contentView = hostingView
        window.appearance = acceptanceAppearance
        window.minSize = NSSize(width: V5.History.width, height: V5.History.height)
        window.setFrame(targetFrame, display: false)
        window.center()
        window.isReleasedWhenClosed = false
        uiAcceptanceWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        waitForWindowActivation(window)
        logAcceptanceEnvironment(window: window, state: state.rawValue)
        emitAcceptanceEnvironmentSamples(window: window, state: state.rawValue, remaining: 24)
    }

    func waitForWindowActivation(_ window: NSWindow) {
        for _ in 0..<1000 where !(window.isKeyWindow && window.isMainWindow && NSApp.isActive) {
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func logAcceptanceEnvironment(window: NSWindow, state: String) {
        let appearanceName = window.effectiveAppearance.name.rawValue
        let scale = window.screen?.backingScaleFactor ?? 0
        emitAcceptanceLog(
            "UI_ACCEPTANCE_ENV state=\(state) appearance=\(appearanceName) scale=\(String(format: "%.1f", scale)) key=\(window.isKeyWindow) main=\(window.isMainWindow) active=\(NSApp.isActive)"
        )
    }

    func emitAcceptanceEnvironmentSamples(window: NSWindow, state: String, remaining: Int) {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.logAcceptanceEnvironment(window: window, state: state)
            self.emitAcceptanceEnvironmentSamples(window: window, state: state, remaining: remaining - 1)
        }
    }

    func emitAcceptanceLog(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
#endif

extension KeyboardShortcuts.Name {
    // 呼出翻译面板的全局快捷键，默认 Option+T（铁律 L-3）
    static let togglePanel = Self("togglePanel", default: .init(.t, modifiers: [.option]))
}
