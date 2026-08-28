import Darwin
import Foundation
import LightTransCore

private actor OutputFailureFlag {
    private var failed = false
    func markFailed() { failed = true }
    func value() -> Bool { failed }
}

@main
struct LightTransCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch CLIOptionsParser.parse(arguments: arguments) {
        case .help:
            CLIOutputWriter.writeHelp()
            exit(CLIExitCode.success.rawValue)
        case .version:
            CLIOutputWriter.writeVersion(cliVersion())
            exit(CLIExitCode.success.rawValue)
        case .usageError(let message):
            CLIOutputWriter.writeUsageError(message)
            exit(CLIExitCode.usageError.rawValue)
        case .run(let options):
            await run(options: options)
        }
    }

    private static func run(options: CLIOptions) async {
        let inputText: String
        do {
            inputText = try CLIInputReader.readInput(textArguments: options.textArguments)
        } catch CLIInputError.conflict {
            CLIOutputWriter.writeUsageError("位置参数与标准输入不能同时提供")
            exit(CLIExitCode.usageError.rawValue)
        } catch {
            CLIOutputWriter.writeUsageError("未提供可翻译文本")
            exit(CLIExitCode.usageError.rawValue)
        }

        let relay = CancellationRelay()
        let signalCoordinator = SignalCoordinator(relay: relay)
        signalCoordinator.start()

        let workflow = TranslationWorkflow()
        let outputFailureFlag = OutputFailureFlag()

        let task = Task<TranslationRunResult, Never> {
            let summary = await workflow.run(
                request: TranslationRequest(text: inputText, mode: options.mode),
                emit: { event in
                    guard options.format == .ndjson else { return }
                    let ok = CLIOutputWriter.writeNDJSONEvent(event)
                    if !ok {
                        await outputFailureFlag.markFailed()
                        await relay.cancel()
                    }
                }
            )
            return TranslationRunResult(summary: summary, outputError: await outputFailureFlag.value())
        }
        await relay.setTask(task)

        let result = await task.value

        var outputError = result.outputError
        if options.format != .ndjson {
            let writeOK = CLIOutputWriter.writeResult(format: options.format, summary: result.summary)
            outputError = outputError || !writeOK
        }

        CLIOutputWriter.writeFailuresToStderr(summary: result.summary)
        if outputError {
            CLIOutputWriter.writeOutputFailureToStderr()
        }
        let exitCode = CLIOutputWriter.exitCode(
            summary: result.summary,
            interrupted: signalCoordinator.didReceiveInterrupt,
            outputError: outputError
        )
        exit(exitCode.rawValue)
    }

    private static func cliVersion() -> String {
        var bufferSize: UInt32 = 0
        _NSGetExecutablePath(nil, &bufferSize)
        var buffer = [CChar](repeating: 0, count: Int(bufferSize))
        guard _NSGetExecutablePath(&buffer, &bufferSize) == 0 else {
            return "development"
        }
        let executableURL = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
        let bundleInfoURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        guard
            let data = try? Data(contentsOf: bundleInfoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let version = plist["CFBundleShortVersionString"] as? String
        else {
            return "development"
        }
        return version
    }
}
