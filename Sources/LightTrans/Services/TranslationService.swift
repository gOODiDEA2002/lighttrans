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
    private let config: ConfigStore
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "translation")

    init(config: ConfigStore = .shared) {
        self.config = config
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
        var baseURL = config.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = config.loadAPIKey(), !apiKey.isEmpty,
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
            "max_tokens": config.maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("翻译请求开始")

        // 4. 发起流式请求
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
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
            continuation.yield(content)
        }
        logger.info("翻译请求结束")
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
