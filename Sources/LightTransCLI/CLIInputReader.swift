import Foundation
import Darwin

enum CLIInputError: Error {
    case conflict
    case empty
}

enum CLIInputReader {
    static func readInput(
        textArguments: [String],
        isStandardInputTerminal: Bool = isatty(STDIN_FILENO) != 0,
        readStandardInput: () -> Data = { FileHandle.standardInput.readDataToEndOfFile() }
    ) throws -> String {
        let hasPipedInput = !isStandardInputTerminal
        if !textArguments.isEmpty && hasPipedInput {
            throw CLIInputError.conflict
        }

        if !textArguments.isEmpty {
            let text = textArguments.joined(separator: " ")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CLIInputError.empty
            }
            return text
        }

        if hasPipedInput {
            let data = readStandardInput()
            guard let text = String(data: data, encoding: .utf8) else {
                throw CLIInputError.empty
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CLIInputError.empty
            }
            return text
        }

        throw CLIInputError.empty
    }
}
