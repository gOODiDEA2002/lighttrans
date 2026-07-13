import SwiftUI

// 程序入口：挂接 AppDelegate 承载状态栏、面板与快捷键
// Settings 场景仅作占位，界面统一由 AppDelegate 手工管理（详见详细设计 3.1）
@main
struct LightTransApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
