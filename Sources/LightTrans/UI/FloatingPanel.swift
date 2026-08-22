import AppKit

// 浮动翻译面板：Spotlight 样式，不抢占当前应用激活、失焦自动隐藏（详细设计 4.1）
// borderless + nonactivatingPanel 确保 contentRect == window.frame（v5 基准：560x600 pt）
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        // 可在任意桌面空间与全屏应用上呼出
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    // 允许输入框获得焦点（对应假设 A-1）
    override var canBecomeKey: Bool { true }

    // 失焦（点击面板外部区域）自动隐藏（FR-9）
    override func resignKey() {
        super.resignKey()
        NSCursor.arrow.set()
        orderOut(nil)
    }

    // Esc 隐藏面板（FR-2）
    override func cancelOperation(_ sender: Any?) {
        NSCursor.arrow.set()
        orderOut(nil)
    }
}
