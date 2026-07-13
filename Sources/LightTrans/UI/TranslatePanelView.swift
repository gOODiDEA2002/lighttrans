import SwiftUI

// 翻译面板界面（详细设计 4.3）
struct TranslatePanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var inputFocused: Bool
    @State private var showCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputArea
            actionRow
            Divider()
            resultArea
        }
        .padding(16)
        .frame(width: 560, height: 440)
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
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    // 操作行：左侧状态文案，右侧翻译/停止按钮（Cmd+Return 触发）
    private var actionRow: some View {
        HStack {
            statusText
            Spacer()
            Button(action: primaryAction) {
                Text(viewModel.isTranslating ? "停止" : "翻译")
                    .frame(minWidth: 56)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder private var statusText: some View {
        switch viewModel.state {
        case .translating:
            Text("翻译中…").font(.callout).foregroundColor(.secondary)
        case .failed(let message):
            Text(message).font(.callout).foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    // 结果区：只读可选中文本，右上角复制按钮
    private var resultArea: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(action: copy) {
                Text(showCopied ? "已复制" : "复制")
            }
            .disabled(viewModel.resultText.isEmpty)

            ScrollView {
                Text(viewModel.resultText)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private func primaryAction() {
        if viewModel.isTranslating {
            viewModel.stopTranslate()
        } else {
            viewModel.startTranslate()
        }
    }

    private func copy() {
        viewModel.copyResult()
        showCopied = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showCopied = false
        }
    }

    private func focusInput() {
        DispatchQueue.main.async { inputFocused = true }
    }
}
