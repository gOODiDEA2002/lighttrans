import AppKit
import Foundation
import os

struct SelectionRequest: Sendable {
    let text: String
    let receivedAt: Date
}

final class SelectionServiceProvider: NSObject {
    var onRequest: (@MainActor (SelectionRequest) -> Void)?
    private let logger = Logger(subsystem: "com.andy.lighttrans", category: "selection-service")

    @objc func openPanelWithSelectedText(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let rawText = pasteboard.string(forType: .string) else {
            logger.error("服务请求未收到纯文本")
            error.pointee = "未收到可处理的文本"
            return
        }

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("服务请求为仅空白文本")
            return
        }

        logger.info("服务请求已接收")
        let request = SelectionRequest(text: rawText, receivedAt: Date())
        Task { @MainActor in
            self.onRequest?(request)
        }
    }
}
