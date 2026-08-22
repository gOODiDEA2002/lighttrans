import SwiftUI

// v5 视觉基准 token（docs/changes/ui-visual-consistency/v5-baseline.md）
// 所有窗口视觉常量集中管理，禁止散落 magic number；不得在代码中自行修改已确认 token
enum V5 {

    // MARK: - 圆角

    static let windowCornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 10
    static let controlCornerRadius: CGFloat = 6

    // MARK: - 间距

    static let windowPadding: CGFloat = 14
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 6

    // MARK: - 字号

    static let titleFontSize: CGFloat = 13
    static let bodyFontSize: CGFloat = 14
    static let settingsBodyFontSize: CGFloat = 13
    static let captionFontSize: CGFloat = 11
    static let pageTitleFontSize: CGFloat = 17

    // MARK: - 卡片填充与边框

    static let cardFill = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.20)
    static let dividerColor = Color.white.opacity(0.14)

    // MARK: - 语义色

    static let accentBlue = Color(red: 10.0/255, green: 132.0/255, blue: 255.0/255)
    static let successGreen = Color(red: 48.0/255, green: 209.0/255, blue: 88.0/255)
    static let warningOrange = Color(red: 255.0/255, green: 159.0/255, blue: 10.0/255)
    static let errorRed = Color(red: 255.0/255, green: 69.0/255, blue: 58.0/255)

    // MARK: - 浮动翻译面板

    enum Panel {
        static let width: CGFloat = 560
        static let height: CGFloat = 600
        static let inputDefault: CGFloat = 100
        static let inputMin: CGFloat = 70
        static let inputMax: CGFloat = 240
        static let handleHeight: CGFloat = 10
        static let handleCapsuleWidth: CGFloat = 36
        static let handleCapsuleHeight: CGFloat = 4
        static let actionRowHeight: CGFloat = 28
        static let titleBarHeight: CGFloat = 28
        static let footerHeight: CGFloat = 20
        static let copyIconSize: CGFloat = 22
    }

    // MARK: - 设置窗口

    enum Settings {
        static let width: CGFloat = 520
        static let height: CGFloat = 450
        static let sidebarContentWidth: CGFloat = 139
        static let dividerWidth: CGFloat = 1
        static let templateTitleBarHeight: CGFloat = 34
        static let fieldSpacing: CGFloat = 10
    }

    // MARK: - 历史窗口

    enum History {
        static let width: CGFloat = 680
        static let height: CGFloat = 480
        static let leftContentWidth: CGFloat = 269
        static let dividerWidth: CGFloat = 1
        static let rightMinWidth: CGFloat = 410
        static let searchHeaderHeight: CGFloat = 76
        static let listRowHeight: CGFloat = 64
        static let selectedRowOpacity: Double = 0.10
        static let selectedRowCornerRadius: CGFloat = 6
    }
}
