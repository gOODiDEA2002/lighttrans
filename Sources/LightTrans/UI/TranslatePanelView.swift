import SwiftUI
import AppKit

// 翻译面板界面（详细设计 13.1、v5 视觉基准）
struct TranslatePanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: PanelViewModel
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    private let autoFocusInput: Bool
    private let characterCountOverride: Int?
    @FocusState private var inputFocused: Bool

    // 动态输入框高度（默认 100 pt，可在 70-240 pt 之间拖拽调节，双击复位）
    @State private var inputHeight: CGFloat
    @State private var isHoveringHandle: Bool = false

    init(
        viewModel: PanelViewModel,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        initialInputHeight: CGFloat = V5.Panel.inputDefault,
        autoFocusInput: Bool = true,
        characterCountOverride: Int? = nil
    ) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.autoFocusInput = autoFocusInput
        self.characterCountOverride = characterCountOverride
        _inputHeight = State(initialValue: PanelInputHeightMath.clamped(initialInputHeight))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: V5.compactSpacing) {
            inputArea
            resizeHandle
            actionRow
            ResultSection(
                title: "直译",
                icon: "character.book.closed",
                state: viewModel.literalState,
                text: viewModel.literalResult,
                onCopy: { viewModel.copy(viewModel.literalResult) }
            )
            .frame(height: resultSectionHeight)
            ResultSection(
                title: "转写",
                icon: "sparkles",
                state: viewModel.rewriteState,
                text: viewModel.rewriteResult,
                onCopy: { viewModel.copy(viewModel.rewriteResult) }
            )
            .frame(height: resultSectionHeight)
            footerBar
        }
        .padding(V5.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectBackground()
                RoundedRectangle(cornerRadius: V5.windowCornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.72) : Color.white.opacity(0.14))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: V5.windowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: V5.windowCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
        .onAppear { if autoFocusInput { focusInput() } }
        .onDisappear { isHoveringHandle = false }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            if autoFocusInput { focusInput() }
        }
        .background(
            Button("") { viewModel.copy(viewModel.literalResult) }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                .opacity(0)
        )
        .background(
            Button("") { viewModel.copy(viewModel.rewriteResult) }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .opacity(0)
        )
        .background(
            Group {
                if viewModel.isTranslating {
                    Button("") { viewModel.stopTranslate() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .opacity(0)
                }
            }
        )
    }

    // 输入区卡片：动态高度调节，文本区与按钮/计数互不遮挡
    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .fill(V5.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                        .strokeBorder(V5.cardBorder, lineWidth: 1)
                )

            TextEditor(text: $viewModel.inputText)
                .font(.system(size: V5.bodyFontSize))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .background(TextEditorScrollConfigurator())
                .padding(.leading, 11)
                .padding(.top, 17)
                .padding(.trailing, 30)
                .padding(.bottom, 22)
                .focused($inputFocused)

            if viewModel.inputText.isEmpty {
                Text("输入待翻译文字，按 \u{2318}\u{21A9} 开始")
                    .font(.system(size: V5.bodyFontSize))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.leading, 16)
                    .padding(.top, 15)
                    .padding(.trailing, 30)
                    .allowsHitTesting(false)
            }

            if !viewModel.inputText.isEmpty {
                Button(action: { viewModel.inputText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: V5.titleFontSize))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(viewModel.isTranslating)
                .help("清空输入")
                .padding(.top, 14)
                .padding(.trailing, 17)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if !viewModel.inputText.isEmpty {
                Text("\(displayedCharacterCount) 字符")
                    .font(.system(size: V5.captionFontSize))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(height: inputHeight)
    }

    private var displayedCharacterCount: Int {
        characterCountOverride ?? viewModel.inputText.count
    }

    private var resultSectionHeight: CGFloat {
        PanelInputHeightMath.resultSectionHeight(inputHeight: inputHeight)
    }

    // 输入框高度调节手柄（AppKit 原生视图，mouseDownCanMoveWindow=false）
    private var resizeHandle: some View {
        ResizeHandleRepresentable(
            inputHeight: $inputHeight,
            isHovering: $isHoveringHandle
        )
        .frame(height: V5.Panel.handleHeight)
        .frame(maxWidth: .infinity)
    }

    // 操作栏：28 pt 圆角容器，空闲态蓝色翻译按钮，生成中显示停止按钮
    private var actionRow: some View {
        HStack(alignment: .center) {
            if viewModel.isTranslating {
                HStack(spacing: V5.compactSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在生成…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Spacer()
            }
            Spacer()
            if viewModel.isTranslating {
                Button(action: { viewModel.stopTranslate() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundColor(V5.errorRed)
                        Text("停止")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(V5.errorRed)
                    }
                    .frame(width: 86, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                            .fill(V5.errorRed.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                            .strokeBorder(V5.errorRed.opacity(0.9), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            } else {
                Button(action: { viewModel.startTranslate() }) {
                    HStack(spacing: 4) {
                        Text("翻译")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        Text("\u{2318}\u{21A9}")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                    .frame(width: 86, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                            .fill(V5.accentBlue)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: V5.Panel.actionRowHeight)
        .background(
            RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                .fill(V5.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V5.controlCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
    }

    // 底部辅助栏：20 pt，快捷键提示与设置/历史入口
    private var footerBar: some View {
        HStack(alignment: .center) {
            Text("\u{2318}\u{21A9} 翻译 \u{00B7} Esc 隐藏")
                .font(.system(size: V5.captionFontSize))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
            HStack(spacing: V5.sectionSpacing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("偏好设置")

                Button(action: onOpenHistory) {
                    Image(systemName: "clock")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("历史记录")
            }
        }
        .frame(height: V5.Panel.footerHeight)
        .padding(.horizontal, 2)
    }

    private func focusInput() {
        DispatchQueue.main.async { inputFocused = true }
    }
}

// 单段结果区：标题栏 + 分隔线 + 可滚动正文（v5 五态完整实现）
private struct ResultSection: View {
    let title: String
    let icon: String
    let state: PanelViewModel.PartState
    let text: String
    let onCopy: () -> Void

    @State private var showCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: V5.compactSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: V5.titleFontSize, weight: .semibold))
                statusView
                Spacer()
                copyButton
            }
            .padding(.horizontal, 10)
            .frame(height: V5.Panel.titleBarHeight)

            Divider()
                .padding(.horizontal, 8)

            ZStack(alignment: .topLeading) {
                if text.isEmpty && state == .idle {
                    Text("等待输入后翻译…")
                        .font(.system(size: V5.settingsBodyFontSize))
                        .foregroundColor(.secondary.opacity(0.78))
                        .padding(10)
                } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          case .failed = state {
                    // v5 局部失败态：正文区显示引导文案
                    Text("当前任务部分失败。按 \u{2318}\u{21A9} 重新执行完整翻译。")
                        .font(.system(size: V5.bodyFontSize))
                        .foregroundColor(.secondary)
                        .padding(10)
                } else {
                    ScrollView {
                        Text(text)
                            .font(.system(size: V5.bodyFontSize))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .fill(V5.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous)
                .strokeBorder(V5.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: V5.cardCornerRadius, style: .continuous))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var statusView: some View {
        switch state {
        case .translating:
            Text("正在\(title)…")
                .font(.caption)
                .foregroundColor(.secondary)
        case .failed(let message):
            Text("失败：\(message)")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        case .stopped:
            Text("已停止")
                .font(.caption)
                .foregroundColor(.secondary)
        case .done:
            Text("已完成")
                .font(.caption)
                .foregroundColor(.secondary)
        case .idle:
            EmptyView()
        }
    }

    // 紧凑方形图标按钮（22x22 pt），复制后原位切换绿色 checkmark 1.5 秒
    private var copyButton: some View {
        Button(action: performCopy) {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12))
                .foregroundColor(showCopied ? V5.successGreen : .secondary)
                .frame(width: V5.Panel.copyIconSize, height: V5.Panel.copyIconSize)
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help(showCopied ? "已复制" : "复制\(title)")
        .accessibilityLabel("复制\(title)")
    }

    private func performCopy() {
        onCopy()
        showCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            showCopied = false
        }
    }
}

// macOS 原生毛玻璃背景（详细设计 13.1）
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - 输入框高度调节手柄（AppKit 原生实现）

private struct ResizeHandleRepresentable: NSViewRepresentable {
    @Binding var inputHeight: CGFloat
    @Binding var isHovering: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ResizeHandleNSView {
        ResizeHandleNSView(coordinator: context.coordinator, height: inputHeight)
    }

    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {
        context.coordinator.parent = self
        nsView.syncFromSwiftUI(height: inputHeight, hovering: isHovering)
    }

    final class Coordinator {
        var parent: ResizeHandleRepresentable
        init(parent: ResizeHandleRepresentable) { self.parent = parent }

        func updateHeight(_ h: CGFloat) { parent.inputHeight = h }
        func updateHover(_ v: Bool) { parent.isHovering = v }

        func resetHeight() {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                parent.inputHeight = V5.Panel.inputDefault
            }
        }
    }
}

private final class ResizeHandleNSView: NSView {
    private let coordinator: ResizeHandleRepresentable.Coordinator
    private let capsuleLayer = CAShapeLayer()
    private var localTrackingArea: NSTrackingArea?

    private var isDragging = false
    private var dragStartY: CGFloat = 0
    private var dragBaseHeight: CGFloat = V5.Panel.inputDefault
    private var currentHeight: CGFloat = V5.Panel.inputDefault

    // 阻止窗口背景拖动吞掉本视图的鼠标事件
    override var mouseDownCanMoveWindow: Bool { false }

    init(coordinator: ResizeHandleRepresentable.Coordinator, height: CGFloat) {
        self.coordinator = coordinator
        self.currentHeight = height
        self.dragBaseHeight = height
        super.init(frame: .zero)
        wantsLayer = true
        capsuleLayer.fillColor = NSColor.secondaryLabelColor.withAlphaComponent(0.25).cgColor
        layer?.addSublayer(capsuleLayer)

        setAccessibilityRole(.slider)
        setAccessibilityLabel("输入框高度调节手柄")
        setAccessibilityMinValue(V5.Panel.inputMin)
        setAccessibilityMaxValue(V5.Panel.inputMax)
        setAccessibilityValue("当前高度 \(Int(height)) pt")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func syncFromSwiftUI(height: CGFloat, hovering: Bool) {
        currentHeight = height
        if !isDragging { dragBaseHeight = height }
        setAccessibilityValue("当前高度 \(Int(height)) pt")
        let alpha: CGFloat = hovering ? 0.6 : 0.25
        capsuleLayer.fillColor = NSColor.secondaryLabelColor.withAlphaComponent(alpha).cgColor
    }

    // MARK: - 布局：36x4 胶囊居中

    override func layout() {
        super.layout()
        let w = V5.Panel.handleCapsuleWidth
        let h = V5.Panel.handleCapsuleHeight
        let x = (bounds.width - w) / 2
        let y = (bounds.height - h) / 2
        capsuleLayer.path = CGPath(
            roundedRect: CGRect(x: x, y: y, width: w, height: h),
            cornerWidth: h / 2, cornerHeight: h / 2, transform: nil
        )
    }

    // MARK: - 鼠标追踪

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = localTrackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        localTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator.updateHover(true)
        NSCursor.resizeUpDown.set()
    }

    override func mouseExited(with event: NSEvent) {
        coordinator.updateHover(false)
        NSCursor.arrow.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { coordinator.updateHover(false) }
    }

    // MARK: - 拖拽与双击

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            coordinator.resetHeight()
            return
        }
        isDragging = true
        dragStartY = event.locationInWindow.y
        dragBaseHeight = currentHeight
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.y - dragStartY
        let newHeight = PanelInputHeightMath.heightAfterDrag(baseHeight: dragBaseHeight, deltaY: delta)
        currentHeight = newHeight
        coordinator.updateHeight(newHeight)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        dragBaseHeight = currentHeight
    }

    // MARK: - VoiceOver 增减（步长 10 pt）

    override func accessibilityPerformIncrement() -> Bool {
        let h = PanelInputHeightMath.clamped(currentHeight + 10)
        currentHeight = h
        dragBaseHeight = h
        coordinator.updateHeight(h)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        let h = PanelInputHeightMath.clamped(currentHeight - 10)
        currentHeight = h
        dragBaseHeight = h
        coordinator.updateHeight(h)
        return true
    }
}
