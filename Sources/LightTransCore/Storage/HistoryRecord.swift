import Foundation

public enum HistoryEffectiveMode: String, Sendable, Equatable {
    case legacy
    case literal
    case rewrite
    case both
}

public struct HistoryRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let time: String
    public let device: String
    public let model: String
    public let status: String
    public let input: String
    public let mode: TranslationMode?
    public let output: String?
    public let literalOutput: String?
    public let rewriteOutput: String?
    public let error: String?

    public init(
        id: String,
        time: String,
        device: String,
        model: String,
        status: String,
        input: String,
        mode: TranslationMode? = nil,
        output: String?,
        literalOutput: String?,
        rewriteOutput: String?,
        error: String?
    ) {
        self.id = id
        self.time = time
        self.device = device
        self.status = status
        self.input = input
        self.model = model
        self.mode = mode
        self.output = output
        self.literalOutput = literalOutput
        self.rewriteOutput = rewriteOutput
        self.error = error
    }

    public var effectiveMode: HistoryEffectiveMode {
        if let mode {
            switch mode {
            case .literal:
                return .literal
            case .rewrite:
                return .rewrite
            case .both:
                return .both
            }
        }
        if literalOutput != nil && rewriteOutput != nil {
            return .both
        }
        if literalOutput != nil {
            return .literal
        }
        if rewriteOutput != nil {
            return .rewrite
        }
        return .legacy
    }
}

public enum HistoryWriteOutcome: Sendable, Equatable {
    case written
    case disabled
    case failed
}
