import AppKit
import os

// 面板状态与翻译调度（详细设计 4.2）
@MainActor
final class PanelViewModel: ObservableObject {
    enum PanelState: Equatable {
        case idle
        case translating
        case done
        case failed(String)
    }

    @Published var inputText: String = ""
    @Published var resultText: String = ""
    @Published var state: PanelState = .idle

    private let service = TranslationService()
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "panel")
    private var currentTask: Task<Void, Never>?
    // 代次：新翻译或取消时用于甄别过期任务，避免旧任务回写状态
    private var generation = 0

    var isTranslating: Bool { state == .translating }

    // 发起翻译：输入为空忽略；进行中则先取消再开新任务
    func startTranslate() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        currentTask?.cancel()
        generation += 1
        let gen = generation
        let input = inputText
        resultText = ""
        state = .translating

        currentTask = Task { @MainActor in
            do {
                for try await chunk in service.translate(text: input) {
                    if gen != generation { return }   // 已被新翻译取代，丢弃过期片段
                    resultText += chunk
                }
                if gen != generation { return }
                // 循环正常结束：被取消（stopTranslate）则回到就绪态并保留已收到的部分译文，否则标记完成
                state = Task.isCancelled ? .idle : .done
            } catch let error as TranslationError {
                if gen != generation { return }
                state = .failed(error.panelMessage)
            } catch is CancellationError {
                // 取消不弹错，静默
            } catch {
                if gen != generation { return }
                state = .failed("接口返回异常：\(error.localizedDescription)")
            }
        }
    }

    // 停止当前翻译（连带断开底层网络，见 TranslationService.onTermination）
    func stopTranslate() {
        currentTask?.cancel()
    }

    // 复制完整译文到剪贴板
    func copyResult() {
        guard !resultText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
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
