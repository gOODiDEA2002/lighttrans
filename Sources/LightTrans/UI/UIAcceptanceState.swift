import Foundation
import CoreGraphics
import LightTransCore

#if DEBUG
// Debug 截图验收状态：集中定义所有冻结态，避免散落 magic string
enum UIAcceptanceState: String, CaseIterable {
    case panelIdle = "panel-idle"
    case panelStreaming = "panel-streaming"
    case panelDone = "panel-done"
    case panelPartialFail = "panel-partial-fail"
    case panelStopped = "panel-stopped"
    case panelHeight70 = "panel-height-70"
    case panelHeight100 = "panel-height-100"
    case panelHeight240 = "panel-height-240"

    case settingsAPIIdle = "settings-api-idle"
    case settingsAPITesting = "settings-api-testing"
    case settingsAPISuccess = "settings-api-success"
    case settingsAPILongError = "settings-api-long-error"
    case settingsTemplatesValid = "settings-templates-valid"
    case settingsTemplatesInvalid = "settings-templates-invalid"

    case historyNormal = "history-normal"
    case historySearchHit = "history-search-hit"
    case historyNoMatch = "history-no-match"
    case historyNoRecords = "history-no-records"
    case historyLongDeviceModel = "history-long-device-model"

    static func parse(arguments: [String]) -> UIAcceptanceState? {
        for (index, arg) in arguments.enumerated() {
            if arg == "--ui-acceptance-state", index + 1 < arguments.count {
                return UIAcceptanceState(rawValue: arguments[index + 1])
            }
            if arg.hasPrefix("--ui-acceptance-state=") {
                let value = String(arg.dropFirst("--ui-acceptance-state=".count))
                return UIAcceptanceState(rawValue: value)
            }
        }
        return nil
    }
}

enum UIMenubarAcceptanceState: String, CaseIterable {
    case dark
    case light
    case pressed

    static func parse(arguments: [String]) -> UIMenubarAcceptanceState? {
        var stateValue: String?
        for (index, arg) in arguments.enumerated() {
            if arg == "--ui-acceptance-menubar-state", index + 1 < arguments.count {
                stateValue = arguments[index + 1]
            } else if arg.hasPrefix("--ui-acceptance-menubar-state=") {
                stateValue = String(arg.dropFirst("--ui-acceptance-menubar-state=".count))
            }
        }
        guard let stateText = stateValue else { return nil }
        return UIMenubarAcceptanceState(rawValue: stateText)
    }
}

struct UIAcceptanceSettingsSnapshot {
    enum Tab {
        case api
        case templates
    }

    enum TestStatus: Equatable {
        case idle
        case testing
        case success(milliseconds: Int)
        case failed(String)
    }

    let selectedTab: Tab
    let apiBaseURL: String
    let modelName: String
    let apiKey: String
    let maxTokensText: String
    let literalTemplate: String
    let rewriteTemplate: String
    let testStatus: TestStatus
}

struct UIAcceptanceHistorySnapshot {
    let records: [HistoryRecord]
    let pendingDevices: Int
    let filter: String
    let selectedID: String?
}

@MainActor
enum UIAcceptancePanelScenario {
    static let baselineInput = "帮我设计一个支持实时数据流的高弹性、高响应性系统架构。"
    static let baselineLiteral = "Help me design a highly resilient and responsive system architecture for real-time data streaming."
    static let baselineRewrite = "Act as a Principal Cloud Architect. Design a resilient and responsive architecture for real-time data streaming, covering scalability, fault tolerance, observability, and disaster recovery."

    static func makeViewModel(for state: UIAcceptanceState) -> PanelViewModel {
        let vm = PanelViewModel()
        vm.inputText = baselineInput

        switch state {
        case .panelIdle:
            vm.inputText = baselineInput
            vm.literalResult = ""
            vm.rewriteResult = ""
            vm.literalState = .idle
            vm.rewriteState = .idle
        case .panelStreaming:
            vm.literalResult = baselineLiteral
            vm.rewriteResult = baselineRewrite
            vm.literalState = .translating
            vm.rewriteState = .translating
        case .panelDone, .panelHeight70, .panelHeight100, .panelHeight240:
            vm.literalResult = baselineLiteral
            vm.rewriteResult = baselineRewrite
            vm.literalState = .done
            vm.rewriteState = .done
        case .panelPartialFail:
            vm.literalResult = baselineLiteral
            vm.rewriteResult = ""
            vm.literalState = .done
            vm.rewriteState = .failed("网络连接超时")
        case .panelStopped:
            vm.literalResult = baselineLiteral
            vm.rewriteResult = baselineRewrite
            vm.literalState = .stopped
            vm.rewriteState = .stopped
        default:
            break
        }
        return vm
    }

    static func inputHeight(for state: UIAcceptanceState) -> CGFloat {
        switch state {
        case .panelHeight70:
            return 70
        case .panelHeight100:
            return 100
        case .panelHeight240:
            return 240
        default:
            return 100
        }
    }

    static func characterCount(for state: UIAcceptanceState) -> Int? {
        switch state {
        case .panelIdle, .panelStreaming, .panelDone, .panelPartialFail, .panelStopped,
             .panelHeight70, .panelHeight100, .panelHeight240:
            return baselineInput.count
        default:
            return nil
        }
    }
}

extension UIAcceptanceSettingsSnapshot {
    static func make(for state: UIAcceptanceState) -> UIAcceptanceSettingsSnapshot {
        let validLiteral = """
        Please provide a direct literal translation for the following text. Do not add explanations or change the structure.

        Text: {{text}}
        """
        let validRewrite = """
        Analyze the following user input and rewrite it into a clear, concise, and professional prompt. Maintain the original intent.

        Input: {{text}}
        """
        switch state {
        case .settingsAPIIdle:
            return .init(
                selectedTab: .api,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-idle-0001",
                maxTokensText: "2000",
                literalTemplate: validLiteral,
                rewriteTemplate: validRewrite,
                testStatus: .idle
            )
        case .settingsAPITesting:
            return .init(
                selectedTab: .api,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-test-0002",
                maxTokensText: "2000",
                literalTemplate: validLiteral,
                rewriteTemplate: validRewrite,
                testStatus: .testing
            )
        case .settingsAPISuccess:
            return .init(
                selectedTab: .api,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-pass-0003",
                maxTokensText: "2000",
                literalTemplate: validLiteral,
                rewriteTemplate: validRewrite,
                testStatus: .success(milliseconds: 185)
            )
        case .settingsAPILongError:
            return .init(
                selectedTab: .api,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-fail-0004",
                maxTokensText: "2000",
                literalTemplate: validLiteral,
                rewriteTemplate: validRewrite,
                testStatus: .failed("连接失败：请求超时（ETIMEDOUT），请检查网络连接、代理设置和上游服务状态后重试。")
            )
        case .settingsTemplatesValid:
            return .init(
                selectedTab: .templates,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-template-valid-5",
                maxTokensText: "2000",
                literalTemplate: validLiteral,
                rewriteTemplate: validRewrite,
                testStatus: .idle
            )
        case .settingsTemplatesInvalid:
            return .init(
                selectedTab: .templates,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-template-miss-6",
                maxTokensText: "2000",
                literalTemplate: """
                Please provide a direct literal translation for the following text.

                Text only.
                """,
                rewriteTemplate: """
                Analyze and rewrite this request into a concise prompt.

                Input only.
                """,
                testStatus: .idle
            )
        default:
            return .init(
                selectedTab: .api,
                apiBaseURL: "https://api.openai.com/v1",
                modelName: "deepseek-chat",
                apiKey: "acceptance-key-default-state-0",
                maxTokensText: "2000",
                literalTemplate: validLiteral,
                rewriteTemplate: validRewrite,
                testStatus: .idle
            )
        }
    }
}

extension UIAcceptanceHistorySnapshot {
    static func make(for state: UIAcceptanceState) -> UIAcceptanceHistorySnapshot {
        let baseRecord = HistoryRecord(
            id: "history-streaming",
            time: "2026-08-20T17:35:02+08:00",
            device: "示例 MacBook Pro",
            model: "deepseek-chat",
            status: "done",
            input: "How to design a resilient and responsive system architecture for real-time streaming?",
            output: nil,
            literalOutput: "如何为实时数据流设计一个具有高弹性与高响应性的系统架构？",
            rewriteOutput: "Act as a Principal Cloud Architect and design a resilient streaming architecture.",
            error: nil
        )
        let secondRecord = HistoryRecord(
            id: "history-architecture",
            time: "2026-08-20T17:35:11+08:00",
            device: "MacBook Pro",
            model: "gpt-4.1-mini",
            status: "done",
            input: "streaming architecture",
            output: nil,
            literalOutput: "如何设计高弹性架构…",
            rewriteOutput: "Act as an architect and provide a robust streaming plan…",
            error: nil
        )
        let thirdRecord = HistoryRecord(
            id: "history-prompt",
            time: "2026-08-20T17:35:21+08:00",
            device: "MacBook Pro",
            model: "deepseek-chat",
            status: "done",
            input: "streaming prompt",
            output: nil,
            literalOutput: "请改写成清晰的提示词…",
            rewriteOutput: "Rewrite into a clear and professional prompt…",
            error: nil
        )
        let longRecord = HistoryRecord(
            id: "history-record-long-device",
            time: "2026-08-20T17:35:02+08:00",
            device: "Example-MacBook-Pro-Office-Device-Name-Very-Long-For-UI-Acceptance",
            model: "gpt-4.1-mini-long-context-window-for-acceptance-layout-check",
            status: "done",
            input: "How to design a resilient and responsive system architecture for real-time streaming?",
            output: nil,
            literalOutput: "如何为实时数据流设计一个具有高弹性与高响应性的系统架构？",
            rewriteOutput: "Act as a Principal Cloud Architect and design a resilient streaming architecture.",
            error: nil
        )

        switch state {
        case .historyNormal:
            let rows = [baseRecord, secondRecord, thirdRecord]
            return .init(records: rows, pendingDevices: 0, filter: "", selectedID: rows.first?.id)
        case .historySearchHit:
            let rows = [baseRecord, secondRecord, thirdRecord]
            return .init(records: rows, pendingDevices: 0, filter: "streaming", selectedID: baseRecord.id)
        case .historyNoMatch:
            let rows = [baseRecord, secondRecord, thirdRecord]
            return .init(records: rows, pendingDevices: 0, filter: "no-hit-keyword", selectedID: nil)
        case .historyNoRecords:
            return .init(records: [], pendingDevices: 0, filter: "", selectedID: nil)
        case .historyLongDeviceModel:
            return .init(records: [longRecord], pendingDevices: 0, filter: "", selectedID: longRecord.id)
        default:
            return .init(records: [baseRecord], pendingDevices: 0, filter: "", selectedID: baseRecord.id)
        }
    }
}
#endif
