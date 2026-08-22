import SwiftUI
import AppKit

// 关闭 TextEditor 的滚动条，避免截图出现右侧滚动指示区
struct TextEditorScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let windowRoot = nsView.window?.contentView else { return }
            for scrollView in collectTextEditorScrollViews(from: windowRoot) {
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.drawsBackground = false
                scrollView.backgroundColor = .clear
            }
        }
    }

    private func collectTextEditorScrollViews(from view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = view as? NSScrollView,
           scrollView.documentView is NSTextView {
            result.append(scrollView)
        }
        for subview in view.subviews {
            result.append(contentsOf: collectTextEditorScrollViews(from: subview))
        }
        return result
    }
}
