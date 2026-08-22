import AppKit
import Foundation
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
    @Published var selectionNotice: String?

    static let selectionAutoTranslateCharacterLimit = 5_000

    struct TranslationConfig: Sendable {
        let modelName: String
        let literalTemplate: String
        let rewriteTemplate: String
        let historyEnabled: Bool
    }

    private let translate: @Sendable (String, String) -> AsyncThrowingStream<String, Error>
    private let loadConfig: @Sendable () -> TranslationConfig
    private let appendHistory: @Sendable (HistoryRecord) -> Void
    private let now: @Sendable () -> Date
    private let loadDeviceName: @Sendable () -> String
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "panel")

    private var currentTask: Task<Void, Never>?
    // 代次：新翻译或取消时用于甄别过期任务，避免旧任务回写状态
    private var generation = 0
    // 由停止操作终止的代次：即使其中一段已失败，聚合历史仍统一记为 stopped
    private var stoppedGeneration: Int?
    private var latestSelectionRequestID: UInt64 = 0

    init(
        translate: @escaping @Sendable (String, String) -> AsyncThrowingStream<String, Error> = { text, template in
            TranslationService().translate(text: text, template: template)
        },
        loadConfig: @escaping @Sendable () -> TranslationConfig = {
            TranslationConfig(
                modelName: ConfigStore.shared.modelName,
                literalTemplate: ConfigStore.shared.literalPromptTemplate,
                rewriteTemplate: ConfigStore.shared.promptTemplate,
                historyEnabled: ConfigStore.shared.historyEnabled
            )
        },
        appendHistory: @escaping @Sendable (HistoryRecord) -> Void = { record in
            HistoryStore.shared.append(record)
        },
        now: @escaping @Sendable () -> Date = { Date() },
        loadDeviceName: @escaping @Sendable () -> String = { Host.current().localizedName ?? "未知设备" }
    ) {
        self.translate = translate
        self.loadConfig = loadConfig
        self.appendHistory = appendHistory
        self.now = now
        self.loadDeviceName = loadDeviceName
    }

    // 任一段处于翻译中即视为翻译中（供按钮在"翻译/停止"间切换）
    var isTranslating: Bool {
        literalState == .translating || rewriteState == .translating
    }

    // 发起翻译：输入为空忽略；进行中则先取消再开新任务（详细设计 11.3）
    func startTranslate() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        selectionNotice = nil
        currentTask?.cancel()
        generation += 1
        let gen = generation
        let input = inputText
        let config = loadConfig()
        literalResult = ""
        rewriteResult = ""
        literalState = .translating
        rewriteState = .translating

        currentTask = Task { @MainActor in
            // 两段并行：各自消费自己的流、回写各自结果与状态
            async let lit: Void = self.runPart(.literal, text: input, template: config.literalTemplate, gen: gen)
            async let rew: Void = self.runPart(.rewrite, text: input, template: config.rewriteTemplate, gen: gen)
            _ = await (lit, rew)

            // 两段都结束后写一条历史记录（已被新翻译顶替则丢弃）
            if gen != self.generation { return }
            let forcedStopped = self.stoppedGeneration == gen
            self.writeHistory(
                input: input,
                model: config.modelName,
                historyEnabled: self.loadConfig().historyEnabled,
                forcedStopped: forcedStopped
            )
            if self.stoppedGeneration == gen {
                self.stoppedGeneration = nil
            }
            if gen == self.generation {
                self.currentTask = nil
            }
        }
    }

    // 接收服务入口送入的外部文本：最新请求优先，旧任务先停止并写入 stopped 历史（详细设计 14.5）
    func acceptExternalText(_ text: String) {
        latestSelectionRequestID &+= 1
        let requestID = latestSelectionRequestID
        Task { @MainActor in
            if let taskToStop = self.currentTask {
                self.stoppedGeneration = self.generation
                taskToStop.cancel()
                await taskToStop.value
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
                self.logger.info("选中文字超过自动翻译字符上限，仅载入面板")
            }
        }
    }

    // 单段翻译：逐片段写入对应结果，结束时按取消/成功/失败置状态
    private func runPart(_ part: Part, text: String, template: String, gen: Int) async {
        do {
            for try await chunk in translate(text, template) {
                if gen != generation { return }   // 已被新翻译取代，丢弃过期片段
                append(part, chunk)
            }
            if gen != generation { return }
            // for-await 被取消时直接结束、不抛 CancellationError，故用 Task.isCancelled 判定（详细设计 4.2）
            setState(part, Task.isCancelled ? .stopped : .done)
        } catch let error as TranslationError {
            if gen != generation { return }
            setState(part, Task.isCancelled ? .stopped : .failed(error.panelMessage))
        } catch is CancellationError {
            if gen != generation { return }
            setState(part, .stopped)
        } catch {
            if gen != generation { return }
            setState(
                part,
                Task.isCancelled ? .stopped : .failed("接口返回异常：\(error.localizedDescription)")
            )
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
    private func writeHistory(
        input: String,
        model: String,
        historyEnabled: Bool,
        forcedStopped: Bool
    ) {
        guard historyEnabled else { return }

        // 聚合状态：任一段失败记 failed，否则任一段停止记 stopped，否则 done
        let states = [literalState, rewriteState]
        let failures = states.compactMap { state -> String? in
            if case .failed(let message) = state { return message }
            return nil
        }
        let status: String
        let error: String?
        if forcedStopped {
            status = "stopped"
            error = nil
        } else if !failures.isEmpty {
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
            time: formatter.string(from: now()),
            device: loadDeviceName(),
            model: model,
            status: status,
            input: input,
            output: nil,
            literalOutput: literalResult,
            rewriteOutput: rewriteResult,
            error: error
        )
        appendHistory(record)
    }

    // 停止当前翻译（连带断开两段底层网络，见 TranslationService.onTermination）
    func stopTranslate() {
        guard let currentTask else { return }
        stoppedGeneration = generation
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
