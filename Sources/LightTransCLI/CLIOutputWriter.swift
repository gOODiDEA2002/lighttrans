import Foundation
import Darwin
import LightTransCore

enum CLIExitCode: Int32 {
    case success = 0
    case routeFailed = 1
    case usageError = 2
    case configurationUnavailable = 3
    case internalError = 70
    case interrupted = 130
}

struct TranslationRunResult {
    let summary: TranslationSummary
    let outputError: Bool
}

enum CLIOutputWriter {
    static func writeUsageError(_ message: String) {
        writeStderr("错误：\(message)\n\(helpText)\n")
    }

    static func writeHelp() {
        writeStdout(helpText + "\n")
    }

    static func writeVersion(_ value: String) {
        writeStdout(value + "\n")
    }

    static func writeResult(format: CLIOutputFormat, summary: TranslationSummary) -> Bool {
        switch format {
        case .text:
            return writeText(summary: summary)
        case .json:
            return writeJSON(summary: summary)
        case .ndjson:
            return true
        }
    }

    static func writeNDJSONEvent(_ event: TranslationEvent) -> Bool {
        guard let line = ndjsonLine(for: event) else { return false }
        return writeStdout(line)
    }

    static func ndjsonLine(for event: TranslationEvent) -> String? {
        let object: [String: Any]
        switch event {
        case .started(let mode, let model):
            object = ["event": "started", "mode": mode.rawValue, "model": model]
        case .chunk(let route, let text):
            object = ["event": "chunk", "route": route.rawValue, "text": text]
        case .routeFinished(let summary):
            var payload: [String: Any] = [
                "event": "route_finished",
                "route": summary.route.rawValue,
                "status": summary.status.rawValue
            ]
            if let failure = summary.failure {
                payload["error"] = ["code": failure.code.rawValue, "message": failure.message]
            }
            object = payload
        case .finished(let summary):
            object = ["event": "finished", "mode": summary.mode.rawValue, "status": summary.status.rawValue]
        }
        return jsonLine(object)
    }

    static func writeFailuresToStderr(summary: TranslationSummary) {
        [summary.literal, summary.rewrite].forEach { route in
            guard let route, let failure = route.failure else { return }
            writeStderr("路由失败（\(route.route.rawValue)）：\(failure.message)\n")
        }
        if summary.history == .failed {
            writeStderr("历史写入失败\n")
        }
    }

    static func writeOutputFailureToStderr() {
        writeStderr("标准输出写入失败\n")
    }

    static func exitCode(summary: TranslationSummary, interrupted: Bool, outputError: Bool) -> CLIExitCode {
        if interrupted {
            return .interrupted
        }
        if outputError {
            return .internalError
        }
        if [summary.literal?.failure?.code, summary.rewrite?.failure?.code].contains(.configurationUnavailable) {
            return .configurationUnavailable
        }
        if summary.status == .failed {
            return .routeFailed
        }
        return .success
    }

    private static var helpText: String {
        """
        用法：
          lt [--mode literal|rewrite|both] [--format text|json|ndjson] [--] [TEXT...]
          lt --help
          lt --version
        """
    }

    private static func writeText(summary: TranslationSummary) -> Bool {
        writeStdout(textOutput(summary: summary))
    }

    static func textOutput(summary: TranslationSummary) -> String {
        var output = ""
        var blocks: [(marker: String, text: String)] = []
        if let literal = summary.literal {
            blocks.append(("-直译-", literal.text))
        }
        if let rewrite = summary.rewrite {
            blocks.append(("-转写-", rewrite.text))
        }
        for block in blocks {
            if !output.isEmpty, !output.hasSuffix("\n") {
                output.append("\n")
            }
            output += "\(block.marker)\n\(block.text)"
        }
        if !output.hasSuffix("\n") {
            output.append("\n")
        }
        return output
    }

    private static func writeJSON(summary: TranslationSummary) -> Bool {
        var object: [String: Any] = [
            "mode": summary.mode.rawValue,
            "status": summary.status.rawValue,
            "model": summary.model
        ]
        if let literal = summary.literal {
            object["literal"] = routeObject(literal)
        }
        if let rewrite = summary.rewrite {
            object["rewrite"] = routeObject(rewrite)
        }
        guard let line = jsonLine(object) else { return false }
        return writeStdout(line)
    }

    private static func routeObject(_ summary: TranslationRouteSummary) -> [String: Any] {
        var object: [String: Any] = [
            "status": summary.status.rawValue,
            "text": summary.text
        ]
        if let failure = summary.failure {
            object["error"] = ["code": failure.code.rawValue, "message": failure.message]
        }
        return object
    }

    private static func jsonLine(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else {
            return nil
        }
        line += "\n"
        return line
    }

    @discardableResult
    private static func writeStdout(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return writeAll(fd: STDOUT_FILENO, data: data)
    }

    private static func writeStderr(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        _ = writeAll(fd: STDERR_FILENO, data: data)
    }

    private static func writeAll(fd: Int32, data: Data) -> Bool {
        var offset = 0
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            while offset < data.count {
                let pointer = baseAddress.advanced(by: offset)
                let written = Darwin.write(fd, pointer, data.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written == 0 {
                    return false
                }
                if errno == EINTR {
                    continue
                }
                return false
            }
            return true
        }
    }
}
