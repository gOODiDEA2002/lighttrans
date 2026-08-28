import AppKit
import Foundation
import LightTransCore

// 面板状态适配器：只映射 Core 事件到 UI，不负责业务调度与历史构造
@MainActor
final class PanelViewModel: ObservableObject {
    enum PartState: Equatable {
        case idle
        case translating
        case done
        case stopped
        case failed(String)
    }

    @Published var inputText: String = ""
    @Published var literalResult: String = ""
    @Published var rewriteResult: String = ""
    @Published var literalState: PartState = .idle
    @Published var rewriteState: PartState = .idle
    @Published var selectionNotice: String?

    static let selectionAutoTranslateCharacterLimit = 5_000

    private let runWorkflow: @Sendable (TranslationRequest, @escaping @Sendable (TranslationEvent) async -> Void) async -> TranslationSummary
    private var currentTask: Task<TranslationSummary, Never>?
    private var generation: UInt64 = 0
    private var latestSelectionRequestID: UInt64 = 0

    init(
        workflow: TranslationWorkflow = TranslationWorkflow()
    ) {
        self.runWorkflow = { request, emit in
            await workflow.run(request: request, emit: emit)
        }
    }

    init(
        runWorkflow: @escaping @Sendable (TranslationRequest, @escaping @Sendable (TranslationEvent) async -> Void) async -> TranslationSummary
    ) {
        self.runWorkflow = runWorkflow
    }

    // 任一段处于翻译中即视为翻译中（供按钮在"翻译/停止"间切换）
    var isTranslating: Bool {
        literalState == .translating || rewriteState == .translating
    }

    func startTranslate() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        selectionNotice = nil
        currentTask?.cancel()
        generation &+= 1
        let gen = generation
        let requestText = inputText

        currentTask = Task {
            await self.runWorkflow(
                TranslationRequest(text: requestText, mode: .both),
                { [weak self] event in
                    await self?.applyEventFromWorkflow(event, generation: gen)
                }
            )
        }
    }

    func acceptExternalText(_ text: String) {
        latestSelectionRequestID &+= 1
        let requestID = latestSelectionRequestID
        Task { @MainActor in
            if let taskToStop = self.currentTask {
                taskToStop.cancel()
                _ = await taskToStop.value
            }

            guard requestID == self.latestSelectionRequestID else { return }

            self.literalResult = ""
            self.rewriteResult = ""
            self.literalState = .idle
            self.rewriteState = .idle
            self.inputText = text

            if text.count <= Self.selectionAutoTranslateCharacterLimit {
                self.selectionNotice = nil
                self.startTranslate()
            } else {
                self.selectionNotice = "选中文字超过 5,000 字符，请确认后翻译"
            }
        }
    }

    private func apply(event: TranslationEvent, generation eventGeneration: UInt64) {
        guard eventGeneration == generation else { return }
        switch event {
        case .started:
            literalResult = ""
            rewriteResult = ""
            literalState = .translating
            rewriteState = .translating
        case .chunk(let route, let text):
            switch route {
            case .literal:
                literalResult += text
            case .rewrite:
                rewriteResult += text
            }
        case .routeFinished(let routeSummary):
            let nextState: PartState
            switch routeSummary.status {
            case .done:
                nextState = .done
            case .stopped:
                nextState = .stopped
            case .failed:
                nextState = .failed(routeSummary.failure?.message ?? "接口返回异常")
            }
            switch routeSummary.route {
            case .literal:
                literalState = nextState
            case .rewrite:
                rewriteState = nextState
            }
        case .finished:
            currentTask = nil
        }
    }

    private func applyEventFromWorkflow(_ event: TranslationEvent, generation: UInt64) async {
        apply(event: event, generation: generation)
    }

    func stopTranslate() {
        guard let currentTask else { return }
        currentTask.cancel()
    }

    func clearInput() {
        inputText = ""
        selectionNotice = nil
    }

    // 复制指定文本到剪贴板（直译、转写各自调用）
    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
