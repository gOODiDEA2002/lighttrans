// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LightTrans",
    // 最低部署目标 macOS 14（铁律 L-1）
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LightTrans", targets: ["LightTrans"]),
        .library(name: "LightTransCore", targets: ["LightTransCore"]),
        .executable(name: "lt", targets: ["LightTransCLI"])
    ],
    dependencies: [
        // 全局快捷键库（决策 D-4）；版本从 2.0.0 起解析
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "LightTransCore"
        ),
        .executableTarget(
            name: "LightTrans",
            dependencies: [
                "LightTransCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .executableTarget(
            name: "LightTransCLI",
            dependencies: [
                "LightTransCore"
            ]
        ),
        .executableTarget(
            name: "LightTransHistoryTestHelper",
            dependencies: ["LightTransCore"],
            path: "Tests/LightTransHistoryTestHelper"
        ),
        .testTarget(
            name: "LightTransTests",
            dependencies: ["LightTrans", "LightTransCore"]
        ),
        .testTarget(
            name: "LightTransCoreTests",
            dependencies: ["LightTransCore", "LightTransHistoryTestHelper"]
        ),
        .testTarget(
            name: "LightTransCLITests",
            dependencies: ["LightTransCLI", "LightTransCore"]
        )
    ]
)
