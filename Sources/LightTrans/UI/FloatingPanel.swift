import AppKit

// 浮动翻译面板：Spotlight 样式，不抢占当前应用激活、失焦自动隐藏（详细设计 4.1）
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .floating
        // 可在任意桌面空间与全屏应用上呼出
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // 隐藏窗口三个标准按钮，保持无边框观感
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    // 允许输入框获得焦点（对应假设 A-1）
    override var canBecomeKey: Bool { true }

    // 失焦（点击面板外部区域）自动隐藏（FR-9）
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    // Esc 隐藏面板（FR-2）
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
