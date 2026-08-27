// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LightTrans",
    // 最低部署目标 macOS 14（铁律 L-1）
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // 全局快捷键库（决策 D-4）；版本从 2.0.0 起解析
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1")
    ],
    targets: [
        // 单一可执行目标
        .executableTarget(
            name: "LightTrans",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .testTarget(
            name: "LightTransTests",
            dependencies: ["LightTrans"]
        )
    ]
)
