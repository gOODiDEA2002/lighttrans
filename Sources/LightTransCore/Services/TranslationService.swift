import Foundation
import os

public struct ModelRequestConfiguration: Sendable, Equatable {
    public let apiBaseURL: String
    public let modelName: String
    public let apiKey: String
    public let maxTokens: Int

    public init(apiBaseURL: String, modelName: String, apiKey: String, maxTokens: Int) {
        self.apiBaseURL = apiBaseURL
        self.modelName = modelName
        self.apiKey = apiKey
        self.maxTokens = maxTokens
    }
}

public struct TranslationService: Sendable {
    public static let connectionTestMaxTokens = 32

    private let session: URLSession
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "translation")

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translate(
        text: String,
        template: String,
        configuration: ModelRequestConfiguration
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(
                        text: text,
                        template: template,
                        configuration: configuration,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as TranslationError {
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    if urlError.code == .cancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(throwing: TranslationError.network(urlError.localizedDescription))
                    }
                } catch {
                    continuation.finish(throwing: TranslationError.badResponse(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        text: String,
        template: String,
        configuration: ModelRequestConfiguration,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var baseURL = configuration.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !model.isEmpty, !apiKey.isEmpty else {
            throw TranslationError.notConfigured
        }
        while baseURL.hasSuffix("/") {
            baseURL.removeLast()
        }
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw TranslationError.badURL
        }

        let prompt: String
        if template.contains("{{text}}") {
            prompt = template.replacingOccurrences(of: "{{text}}", with: text)
        } else {
            prompt = template + "\n\n" + text
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "max_tokens": configuration.maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("翻译请求开始")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.badResponse("无有效的 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line
            }
            throw mapHTTPError(status: http.statusCode, body: bodyText)
        }

        var receivedContent = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else {
                continue
            }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty {
                continue
            }
            if payload == "[DONE]" {
                break
            }
            guard
                let data = payload.data(using: .utf8),
                let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
                let content = chunk.choices.first?.delta.content,
                !content.isEmpty
            else {
                continue
            }
            receivedContent = true
            continuation.yield(content)
        }
        guard receivedContent else {
            throw TranslationError.badResponse("流式响应未包含有效内容")
        }
        logger.info("翻译请求结束")
    }

    public func testConnection(baseURL: String, model: String, apiKey: String) async throws -> TimeInterval {
        var cleanBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBaseURL.isEmpty, !cleanModel.isEmpty, !cleanKey.isEmpty else {
            throw TranslationError.notConfigured
        }
        while cleanBaseURL.hasSuffix("/") {
            cleanBaseURL.removeLast()
        }
        guard let url = URL(string: cleanBaseURL + "/chat/completions") else {
            throw TranslationError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": cleanModel,
            "stream": false,
            "max_tokens": Self.connectionTestMaxTokens,
            "messages": [["role": "user", "content": "Reply with OK."]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let start = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw CancellationError()
            }
            throw TranslationError.network(urlError.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranslationError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.badResponse("无有效的 HTTP 响应")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw mapHTTPError(status: http.statusCode, body: bodyText)
        }
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = obj["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any]
        else {
            throw TranslationError.badResponse("接口返回格式异常")
        }
        let content = message["content"] as? String ?? ""
        guard !content.isEmpty else {
            if firstChoice["finish_reason"] as? String == "length" {
                throw TranslationError.badResponse("测试输出 Token 不足，模型未返回正文")
            }
            throw TranslationError.badResponse("接口返回格式异常")
        }
        return Date().timeIntervalSince(start)
    }

    private func mapHTTPError(status: Int, body: String) -> TranslationError {
        var errorCode = ""
        var errorMessage = ""
        if
            let data = body.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let err = obj["error"] as? [String: Any]
        {
            errorCode = (err["code"] as? String) ?? ""
            errorMessage = (err["message"] as? String) ?? ""
        }
        if status == 401 {
            return .invalidKey
        }
        if status == 402 || errorCode.lowercased().contains("insufficient") {
            return .insufficientQuota
        }
        if status == 429 {
            return .rateLimited
        }
        if status == 404 {
            return .badURL
        }
        let summary = errorMessage.isEmpty ? body : errorMessage
        return .badResponse(String(summary.prefix(100)))
    }
}

private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}
