import Foundation
import os

// 翻译错误分类（详细设计第 7 节）。中文文案由界面层映射，服务层只负责归类。
enum TranslationError: Error, Equatable {
    case notConfigured        // 配置缺失
    case invalidKey           // HTTP 401
    case rateLimited          // HTTP 429
    case insufficientQuota    // HTTP 402，或响应体 error.code 含 insufficient
    case badURL               // 地址无法解析 / HTTP 404
    case network(String)      // URLError（断网、超时、无法连接）
    case badResponse(String)  // 其他非 2xx 或响应格式异常
}

// 翻译服务：渲染提示词、调用 OpenAI 兼容流式接口、解析 SSE（详细设计第 6 节）
struct TranslationService {
    static let connectionTestMaxTokens = 32

    struct RequestConfiguration: Sendable {
        let apiBaseURL: String
        let modelName: String
        let apiKey: String?
        let maxTokens: Int
    }

    private let loadConfiguration: @Sendable () -> RequestConfiguration
    private let session: URLSession
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "translation")

    init(config: ConfigStore = .shared, session: URLSession = .shared) {
        self.loadConfiguration = {
            RequestConfiguration(
                apiBaseURL: config.apiBaseURL,
                modelName: config.modelName,
                apiKey: config.loadAPIKey(),
                maxTokens: config.maxTokens
            )
        }
        self.session = session
    }

    init(
        session: URLSession,
        loadConfiguration: @escaping @Sendable () -> RequestConfiguration
    ) {
        self.loadConfiguration = loadConfiguration
        self.session = session
    }

    // 入口：返回一个陆续吐出译文片段、可能中途报错的异步序列（系统设计第 6 节、详细设计 11.2）
    // template 由调用方传入（直译或转写模板），其余配置仍从 ConfigStore 读取
    func translate(text: String, template: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(text: text, template: template, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as TranslationError {
                    continuation.finish(throwing: error)
                } catch let urlError as URLError {
                    // 取消触发的 URLError 归为取消，其余归为网络错误
                    if urlError.code == .cancelled {
                        continuation.finish(throwing: CancellationError())
                    } else {
                        continuation.finish(throwing: TranslationError.network(urlError.localizedDescription))
                    }
                } catch {
                    continuation.finish(throwing: TranslationError.badResponse(error.localizedDescription))
                }
            }
            // 调用方取消时，连带取消底层网络任务，连接立即断开、不再计费（详细设计 6.3）
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(text: String,
                     template: String,
                     continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        // 1. 读配置并校验
        let configuration = loadConfiguration()
        var baseURL = configuration.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty,
              !baseURL.isEmpty, !model.isEmpty else {
            throw TranslationError.notConfigured
        }
        // 去除 baseURL 末尾多余的 /
        while baseURL.hasSuffix("/") { baseURL.removeLast() }
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw TranslationError.badURL
        }

        // 2. 渲染提示词：含 {{text}} 则替换，否则以"模板 + 空行 + 原文"兜底
        let prompt: String
        if template.contains("{{text}}") {
            prompt = template.replacingOccurrences(of: "{{text}}", with: text)
        } else {
            prompt = template + "\n\n" + text
        }

        // 3. 构造请求
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

        // 4. 发起流式请求
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.badResponse("无有效的 HTTP 响应")
        }

        // 5. 状态码非 2xx：读响应体尽力解析错误信息并归类
        guard (200...299).contains(http.statusCode) else {
            var bodyText = ""
            for try await line in bytes.lines { bodyText += line }
            let mapped = mapHTTPError(status: http.statusCode, body: bodyText)
            logger.error("翻译请求失败：HTTP \(http.statusCode)")
            throw mapped
        }

        // 6. 逐行解析 SSE（详细设计 6.2）
        var receivedContent = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty { continue }
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
                  let content = chunk.choices.first?.delta.content,
                  !content.isEmpty else {
                // 坏行或无内容行跳过，不中断整个流
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

    // 轻量连通性探测接口（详细设计 13.2）
    // 构造 max_tokens: 32 的非流式探测请求，超时 10 秒，支持取消，不写历史记录
    func testConnection(baseURL: String, model: String, apiKey: String) async throws -> TimeInterval {
        var cleanBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanBaseURL.isEmpty, !cleanModel.isEmpty else {
            throw TranslationError.notConfigured
        }
        while cleanBaseURL.hasSuffix("/") { cleanBaseURL.removeLast() }
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

        // 解码非流式响应并校验 choices[0].message.content 是否有效
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
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

    // HTTP 错误归类（详细设计第 7 节）
    private func mapHTTPError(status: Int, body: String) -> TranslationError {
        var errorCode = ""
        var errorMessage = ""
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any] {
            errorCode = (err["code"] as? String) ?? ""
            errorMessage = (err["message"] as? String) ?? ""
        }
        if status == 401 { return .invalidKey }
        if status == 402 || errorCode.lowercased().contains("insufficient") { return .insufficientQuota }
        if status == 429 { return .rateLimited }
        if status == 404 { return .badURL }
        let summary = errorMessage.isEmpty ? body : errorMessage
        return .badResponse(String(summary.prefix(100)))
    }
}

// SSE 数据行的最小解码模型（详细设计 6.2）
private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}
