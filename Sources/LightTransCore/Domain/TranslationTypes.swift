import Foundation

public enum TranslationRoute: String, Codable, Sendable, Equatable {
    case literal
    case rewrite
}

public enum TranslationMode: String, Codable, Sendable, Equatable {
    case literal
    case rewrite
    case both

    public var routes: [TranslationRoute] {
        switch self {
        case .literal:
            return [.literal]
        case .rewrite:
            return [.rewrite]
        case .both:
            return [.literal, .rewrite]
        }
    }
}

public enum TranslationRouteStatus: String, Codable, Sendable, Equatable {
    case done
    case stopped
    case failed
}

public enum TranslationStatus: String, Codable, Sendable, Equatable {
    case done
    case stopped
    case failed
}

public struct TranslationFailure: Codable, Sendable, Equatable {
    public let code: TranslationErrorCode
    public let message: String

    public init(code: TranslationErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public struct TranslationRequest: Sendable, Equatable {
    public let text: String
    public let mode: TranslationMode

    public init(text: String, mode: TranslationMode) {
        self.text = text
        self.mode = mode
    }
}

public struct TranslationRouteSummary: Sendable, Equatable {
    public let route: TranslationRoute
    public let status: TranslationRouteStatus
    public let text: String
    public let failure: TranslationFailure?

    public init(route: TranslationRoute, status: TranslationRouteStatus, text: String, failure: TranslationFailure?) {
        self.route = route
        self.status = status
        self.text = text
        self.failure = failure
    }
}

public enum TranslationEvent: Sendable, Equatable {
    case started(mode: TranslationMode, model: String)
    case chunk(route: TranslationRoute, text: String)
    case routeFinished(TranslationRouteSummary)
    case finished(TranslationSummary)
}

public struct TranslationSummary: Sendable, Equatable {
    public let mode: TranslationMode
    public let status: TranslationStatus
    public let model: String
    public let literal: TranslationRouteSummary?
    public let rewrite: TranslationRouteSummary?
    public let history: HistoryWriteOutcome

    public init(
        mode: TranslationMode,
        status: TranslationStatus,
        model: String,
        literal: TranslationRouteSummary?,
        rewrite: TranslationRouteSummary?,
        history: HistoryWriteOutcome
    ) {
        self.mode = mode
        self.status = status
        self.model = model
        self.literal = literal
        self.rewrite = rewrite
        self.history = history
    }
}
