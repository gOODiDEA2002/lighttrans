import Foundation
import LightTransCore

enum CLIOutputFormat: String, Equatable {
    case text
    case json
    case ndjson
}

enum CLIParseResult {
    case help
    case version
    case run(options: CLIOptions)
    case usageError(String)
}

struct CLIOptions {
    let mode: TranslationMode
    let format: CLIOutputFormat
    let textArguments: [String]
}

enum CLIOptionsParser {
    static func parse(arguments: [String]) -> CLIParseResult {
        if arguments == ["--help"] {
            return .help
        }
        if arguments == ["--version"] {
            return .version
        }

        var mode: TranslationMode = .both
        var format: CLIOutputFormat = .text
        var textArguments: [String] = []
        var index = 0
        var seenMode = false
        var seenFormat = false
        var passthrough = false

        while index < arguments.count {
            let current = arguments[index]
            if passthrough {
                textArguments.append(current)
                index += 1
                continue
            }

            if current == "--" {
                passthrough = true
                index += 1
                continue
            }

            if current == "--mode" || current == "--format" {
                guard index + 1 < arguments.count else {
                    return .usageError("\(current) 缺少取值")
                }
                let value = arguments[index + 1]
                if current == "--mode" {
                    if seenMode { return .usageError("--mode 不能重复") }
                    guard let parsedMode = TranslationMode(rawValue: value) else {
                        return .usageError("--mode 仅支持 literal|rewrite|both")
                    }
                    mode = parsedMode
                    seenMode = true
                } else {
                    if seenFormat { return .usageError("--format 不能重复") }
                    guard let parsedFormat = CLIOutputFormat(rawValue: value) else {
                        return .usageError("--format 仅支持 text|json|ndjson")
                    }
                    format = parsedFormat
                    seenFormat = true
                }
                index += 2
                continue
            }

            if current.hasPrefix("--mode=") {
                if seenMode { return .usageError("--mode 不能重复") }
                let value = String(current.dropFirst("--mode=".count))
                guard let parsedMode = TranslationMode(rawValue: value) else {
                    return .usageError("--mode 仅支持 literal|rewrite|both")
                }
                mode = parsedMode
                seenMode = true
                index += 1
                continue
            }

            if current.hasPrefix("--format=") {
                if seenFormat { return .usageError("--format 不能重复") }
                let value = String(current.dropFirst("--format=".count))
                guard let parsedFormat = CLIOutputFormat(rawValue: value) else {
                    return .usageError("--format 仅支持 text|json|ndjson")
                }
                format = parsedFormat
                seenFormat = true
                index += 1
                continue
            }

            if current.hasPrefix("--") {
                return .usageError("未知参数：\(current)")
            }

            textArguments.append(current)
            index += 1
        }

        return .run(options: CLIOptions(mode: mode, format: format, textArguments: textArguments))
    }
}
