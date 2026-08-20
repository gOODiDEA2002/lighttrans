import SwiftUI
import AppKit

// 翻译面板界面（详细设计 13.1、UI 方案 v3.0）
struct TranslatePanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputArea
            actionRow
            // 结果区两块：直译、转写，平分剩余高度并独立滚动与复制
            ResultSection(
                title: "直译",
                icon: "character.book.closed",
                state: viewModel.literalState,
                text: viewModel.literalResult,
                onCopy: { viewModel.copy(viewModel.literalResult) }
            )
            ResultSection(
                title: "转写",
                icon: "sparkles",
                state: viewModel.rewriteState,
                text: viewModel.rewriteResult,
                onCopy: { viewModel.copy(viewModel.rewriteResult) }
            )
            footerBar
        }
        .padding(14)
        .frame(width: 560, height: 600)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { focusInput() }
        // 每次面板呼出重新聚焦输入框
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            focusInput()
        }
        // 局部快捷键支持：Cmd+Shift+1 复制直译，Cmd+Shift+2 复制转写
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
    }

    // 输入区卡片：高度 100 pt，文本区与右侧按钮/下方计数完全避让，防止遮挡
    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.leading, 8)
                .padding(.top, 6)
                .padding(.trailing, 28)  // 右侧预留 28 pt 避让清空按钮
                .padding(.bottom, 22)   // 底部预留 22 pt 避让字符统计
                .focused($inputFocused)

            if viewModel.inputText.isEmpty {
                Text("输入要翻译的文字，Cmd+Return 开始翻译")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.leading, 13)
                    .padding(.top, 7)
                    .padding(.trailing, 28)
                    .allowsHitTesting(false)
            }

            // 右上角：一键清空按钮
            if !viewModel.inputText.isEmpty {
                Button(action: { viewModel.inputText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isTranslating)
                .help("清空输入")
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            // 右下角：字符统计
            if !viewModel.inputText.isEmpty {
                Text("\(viewModel.inputText.count) 字符")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(height: 100)
    }

    // 操作栏：高度 28 pt，生成中切换为警示样式「停止」按钮
    private var actionRow: some View {
        HStack(alignment: .center) {
            if viewModel.isTranslating {
                HStack(spacing: 6) {
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
                        Text("停止")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(minWidth: 60, minHeight: 22)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button(action: { viewModel.startTranslate() }) {
                    HStack(spacing: 4) {
                        Text("翻译")
                            .font(.system(size: 12, weight: .medium))
                        Text("⌘↩")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(minWidth: 60, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(height: 28)
    }

    // 底部辅助栏：高度 20 pt，快捷键提示与设置/历史直达入口
    private var footerBar: some View {
        HStack(alignment: .center) {
            Text("⌘↩ 翻译 · Esc 隐藏")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
            HStack(spacing: 12) {
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
        .frame(height: 20)
        .padding(.horizontal, 2)
    }

    private func focusInput() {
        DispatchQueue.main.async { inputFocused = true }
    }
}

// 单段结果区：小标题 + 局部独立状态 + 复制反馈按钮 + 独立滚动文字卡片（详细设计 13.1）
private struct ResultSection: View {
    let title: String
    let icon: String
    let state: PanelViewModel.PartState
    let text: String
    let onCopy: () -> Void

    @State private var showCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 头部栏：图标 + 标题 + 局部状态 + 复制按钮
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                statusView
                Spacer()
                copyButton
            }
            .frame(height: 22)

            // 正文卡片容器
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                if text.isEmpty && state == .idle {
                    Text("等待输入后翻译…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(10)
                } else {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
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

    private var copyButton: some View {
        Button(action: performCopy) {
            HStack(spacing: 3) {
                if showCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("已复制")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                    Text("复制")
                        .font(.system(size: 11))
                }
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(text.isEmpty)
    }

    private func performCopy() {
        onCopy()
        showCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showCopied = false
        }
    }
}

// macOS 原生毛玻璃背景（详细设计 13.1：NSVisualEffectView，材质为 .popover，blendingMode 为 .behindWindow）
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
