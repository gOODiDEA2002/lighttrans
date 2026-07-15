import SwiftUI

// 翻译面板界面（详细设计 4.3、11.5）
struct TranslatePanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputArea
            actionRow
            Divider()
            // 结果区上下两块：直译、转写，各自独立滚动与复制
            ResultSection(title: "直译",
                          state: viewModel.literalState,
                          text: viewModel.literalResult,
                          onCopy: { viewModel.copy(viewModel.literalResult) })
            ResultSection(title: "转写",
                          state: viewModel.rewriteState,
                          text: viewModel.rewriteResult,
                          onCopy: { viewModel.copy(viewModel.rewriteResult) })
        }
        .padding(16)
        .frame(width: 560, height: 600)
        .onAppear { focusInput() }
        // 每次面板呼出重新聚焦输入框
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
            focusInput()
        }
    }

    // 输入区：多行编辑，空时显示占位提示
    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.inputText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .focused($inputFocused)
            if viewModel.inputText.isEmpty {
                Text("输入要翻译的文字，Cmd+Return 开始翻译")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    // 与 TextEditor 内光标落点对齐：外层 padding(6) + NSTextView 行首内边距
                    .padding(.leading, 11)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    // 操作行：右侧翻译/停止按钮（Cmd+Return 触发）
    private var actionRow: some View {
        HStack {
            Spacer()
            Button(action: primaryAction) {
                Text(viewModel.isTranslating ? "停止" : "翻译")
                    .frame(minWidth: 56)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func primaryAction() {
        if viewModel.isTranslating {
            viewModel.stopTranslate()
        } else {
            viewModel.startTranslate()
        }
    }

    private func focusInput() {
        DispatchQueue.main.async { inputFocused = true }
    }
}

// 单段结果区：小标题 + 状态 + 复制按钮 + 独立滚动的只读文本（详细设计 11.5）
private struct ResultSection: View {
    let title: String
    let state: PanelViewModel.PartState
    let text: String
    let onCopy: () -> Void

    @State private var showCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout).bold()
                statusText
                Spacer()
                Button(action: copy) {
                    Text(showCopied ? "已复制" : "复制")
                }
                .disabled(text.isEmpty)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    @ViewBuilder private var statusText: some View {
        switch state {
        case .translating:
            Text("翻译中…").font(.caption).foregroundColor(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundColor(.red).lineLimit(1)
        case .stopped:
            Text("已停止").font(.caption).foregroundColor(.secondary)
        default:
            EmptyView()
        }
    }

    private func copy() {
        onCopy()
        showCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showCopied = false
        }
    }
}
