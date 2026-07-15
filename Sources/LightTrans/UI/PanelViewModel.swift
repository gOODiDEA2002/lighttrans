import AppKit
import os

// 面板状态与翻译调度（详细设计 4.2、11.3）
@MainActor
final class PanelViewModel: ObservableObject {
    // 单段（直译或转写）的状态
    enum PartState: Equatable {
        case idle
        case translating
        case done
        case stopped
        case failed(String)
    }

    // 区分两段，供内部路由结果与状态
    private enum Part {
        case literal   // 直译
        case rewrite   // 转写
    }

    @Published var inputText: String = ""
    @Published var literalResult: String = ""
    @Published var rewriteResult: String = ""
    @Published var literalState: PartState = .idle
    @Published var rewriteState: PartState = .idle

    private let service = TranslationService()
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "panel")
    private var currentTask: Task<Void, Never>?
    // 代次：新翻译或取消时用于甄别过期任务，避免旧任务回写状态
    private var generation = 0

    // 任一段处于翻译中即视为翻译中（供按钮在"翻译/停止"间切换）
    var isTranslating: Bool {
        literalState == .translating || rewriteState == .translating
    }

    // 发起翻译：输入为空忽略；进行中则先取消再开新任务（详细设计 11.3）
    func startTranslate() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        currentTask?.cancel()
        generation += 1
        let gen = generation
        let input = inputText
        literalResult = ""
        rewriteResult = ""
        literalState = .translating
        rewriteState = .translating

        let model = ConfigStore.shared.modelName
        let literalTemplate = ConfigStore.shared.literalPromptTemplate
        let rewriteTemplate = ConfigStore.shared.promptTemplate

        currentTask = Task { @MainActor in
            // 两段并行：各自消费自己的流、回写各自结果与状态
            async let lit: Void = self.runPart(.literal, text: input, template: literalTemplate, gen: gen)
            async let rew: Void = self.runPart(.rewrite, text: input, template: rewriteTemplate, gen: gen)
            _ = await (lit, rew)

            // 两段都结束后写一条历史记录（已被新翻译顶替则丢弃）
            if gen != self.generation { return }
            self.writeHistory(input: input, model: model)
        }
    }

    // 单段翻译：逐片段写入对应结果，结束时按取消/成功/失败置状态
    private func runPart(_ part: Part, text: String, template: String, gen: Int) async {
        do {
            for try await chunk in service.translate(text: text, template: template) {
                if gen != generation { return }   // 已被新翻译取代，丢弃过期片段
                append(part, chunk)
            }
            if gen != generation { return }
            // for-await 被取消时直接结束、不抛 CancellationError，故用 Task.isCancelled 判定（详细设计 4.2）
            setState(part, Task.isCancelled ? .stopped : .done)
        } catch let error as TranslationError {
            if gen != generation { return }
            setState(part, .failed(error.panelMessage))
        } catch is CancellationError {
            // 取消不弹错，静默
        } catch {
            if gen != generation { return }
            setState(part, .failed("接口返回异常：\(error.localizedDescription)"))
        }
    }

    private func append(_ part: Part, _ chunk: String) {
        switch part {
        case .literal: literalResult += chunk
        case .rewrite: rewriteResult += chunk
        }
    }

    private func setState(_ part: Part, _ state: PartState) {
        switch part {
        case .literal: literalState = state
        case .rewrite: rewriteState = state
        }
    }

    // 两段结束后写入一条历史记录（详细设计 11.3、11.4）
    // 历史开关关闭时跳过；写入失败由 HistoryStore 内部只记日志，不打扰用户
    private func writeHistory(input: String, model: String) {
        guard ConfigStore.shared.historyEnabled else { return }

        // 聚合状态：任一段失败记 failed，否则任一段停止记 stopped，否则 done
        let states = [literalState, rewriteState]
        let failures = states.compactMap { state -> String? in
            if case .failed(let message) = state { return message }
            return nil
        }
        let status: String
        let error: String?
        if !failures.isEmpty {
            status = "failed"
            error = failures.joined(separator: "；")
        } else if states.contains(.stopped) {
            status = "stopped"
            error = nil
        } else {
            status = "done"
            error = nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let record = HistoryRecord(
            id: UUID().uuidString,
            time: formatter.string(from: Date()),
            device: Host.current().localizedName ?? "未知设备",
            model: model,
            status: status,
            input: input,
            output: nil,
            literalOutput: literalResult,
            rewriteOutput: rewriteResult,
            error: error
        )
        HistoryStore.shared.append(record)
    }

    // 停止当前翻译（连带断开两段底层网络，见 TranslationService.onTermination）
    func stopTranslate() {
        currentTask?.cancel()
    }

    // 复制指定文本到剪贴板（直译、转写各自调用）
    func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// TranslationError 到面板中文文案的映射（详细设计第 7 节，界面层职责）
extension TranslationError {
    var panelMessage: String {
        switch self {
        case .notConfigured: return "请先在设置中填写接口地址、模型名和 API Key"
        case .invalidKey: return "API Key 无效，请检查设置"
        case .rateLimited: return "请求过于频繁，请稍后再试"
        case .insufficientQuota: return "账户余额不足或额度已用完"
        case .badURL: return "接口地址不正确，请检查设置"
        case .network: return "网络连接失败，请检查网络后重试"
        case .badResponse(let summary):
            return "接口返回异常：\(String(summary.prefix(100)))"
        }
    }
}
