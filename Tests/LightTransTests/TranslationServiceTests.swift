import Foundation
import XCTest
@testable import LightTrans

final class TranslationServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testTranslateParsesStreamingContent() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            let payload = """
            data: {"choices":[{"delta":{"content":"轻"}}]}

            data: {"choices":[{"delta":{"content":"译"}}]}

            data: [DONE]

            """
            return (response, Data(payload.utf8))
        }

        var output = ""
        for try await chunk in makeService().translate(text: "source", template: "{{text}}") {
            output += chunk
        }

        XCTAssertEqual(output, "轻译")
    }

    func testTranslateRejectsSuccessfulResponseWithoutContent() async {
        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data("data: [DONE]\n\n".utf8))
        }

        do {
            for try await _ in makeService().translate(text: "source", template: "{{text}}") {}
            XCTFail("空流式响应不应被判定为成功")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .badResponse("流式响应未包含有效内容"))
        } catch {
            XCTFail("收到非预期错误：\(error)")
        }
    }

    func testConnectionMapsUnauthorizedResponse() async {
        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)
            )
            return (response, Data(#"{"error":{"message":"unauthorized"}}"#.utf8))
        }

        do {
            _ = try await makeService().testConnection(
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "test-key"
            )
            XCTFail("401 响应不应通过连接测试")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .invalidKey)
        } catch {
            XCTFail("收到非预期错误：\(error)")
        }
    }

    func testConnectionAcceptsValidResponse() async throws {
        XCTAssertEqual(TranslationService.connectionTestMaxTokens, 32)

        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            let data = Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
            return (response, data)
        }

        let elapsed = try await makeService().testConnection(
            baseURL: "https://example.com/v1/",
            model: "test-model",
            apiKey: "test-key"
        )

        XCTAssertGreaterThanOrEqual(elapsed, 0)
    }

    func testConnectionReportsOutputTokenLimit() async {
        MockURLProtocol.requestHandler = { request in
            let response = try XCTUnwrap(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            let data = Data(
                #"{"choices":[{"finish_reason":"length","message":{"content":"","reasoning_content":"hidden"}}]}"#.utf8
            )
            return (response, data)
        }

        do {
            _ = try await makeService().testConnection(
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "test-key"
            )
            XCTFail("输出 Token 不足时不应通过连接测试")
        } catch let error as TranslationError {
            XCTAssertEqual(error, .badResponse("测试输出 Token 不足，模型未返回正文"))
        } catch {
            XCTFail("收到非预期错误：\(error)")
        }
    }

    private func makeService() -> TranslationService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return TranslationService(session: session) {
            .init(
                apiBaseURL: "https://example.com/v1",
                modelName: "test-model",
                apiKey: "test-key",
                maxTokens: 2000
            )
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
