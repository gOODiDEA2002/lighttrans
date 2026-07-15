#!/usr/bin/env bash
# 构建并打包 LightTrans.app（ad-hoc 本地签名，仅本机使用）
# 依据详细设计第 8 节。任何一步失败立即退出。
set -euo pipefail

# 切到工程根目录（脚本位于 Scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="LightTrans"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_PATH="Resources/AppIcon.icns"
KEYBOARD_SHORTCUTS_CHECKOUT=".build/checkouts/KeyboardShortcuts"
KEYBOARD_SHORTCUTS_RECORDER="${KEYBOARD_SHORTCUTS_CHECKOUT}/Sources/KeyboardShortcuts/Recorder.swift"
KEYBOARD_SHORTCUTS_PATCH="${ROOT_DIR}/Patches/KeyboardShortcuts-2.4.0-remove-previews.patch"
EXPECTED_KEYBOARD_SHORTCUTS_REVISION="1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27"

if [[ ! -f "${ICON_PATH}" ]]; then
    echo "错误：找不到应用图标 ${ICON_PATH}，请先运行 bash Scripts/generate-app-icon.sh" >&2
    exit 1
fi

# KeyboardShortcuts 2.4.0 含三个只供 Xcode 使用的 SwiftUI #Preview。
# 目标机器可能只有 Command Line Tools，构建前删除这些预览代码，运行时代码不变。
echo "==> 解析 Swift Package 依赖"
swift package resolve
if [[ ! -f "${KEYBOARD_SHORTCUTS_RECORDER}" || ! -f "${KEYBOARD_SHORTCUTS_PATCH}" ]]; then
    echo "错误：找不到 KeyboardShortcuts 源码或兼容补丁" >&2
    exit 1
fi
ACTUAL_KEYBOARD_SHORTCUTS_REVISION="$(git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" rev-parse HEAD)"
if [[ "${ACTUAL_KEYBOARD_SHORTCUTS_REVISION}" != "${EXPECTED_KEYBOARD_SHORTCUTS_REVISION}" ]]; then
    echo "错误：KeyboardShortcuts 版本与补丁不匹配，请先更新兼容补丁" >&2
    exit 1
fi
if grep -q '^[[:space:]]*#Preview' "${KEYBOARD_SHORTCUTS_RECORDER}"; then
    echo "==> 移除 KeyboardShortcuts 的 Xcode 预览代码"
    git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" apply --check "${KEYBOARD_SHORTCUTS_PATCH}"
    git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" apply "${KEYBOARD_SHORTCUTS_PATCH}"
fi
if grep -q '^[[:space:]]*#Preview' "${KEYBOARD_SHORTCUTS_RECORDER}"; then
    echo "错误：KeyboardShortcuts 预览代码未成功移除" >&2
    exit 1
fi

# 1. release 构建
echo "==> swift build -c release"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

# 2. 组装 .app 目录结构（先清理旧产物）
echo "==> 组装 ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 3. 复制可执行文件与 Info.plist
cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ICON_PATH}" "${RESOURCES_DIR}/AppIcon.icns"

# 3.1 复制依赖生成的资源包（.bundle）到可执行文件旁，供运行时定位资源
#     （如 KeyboardShortcuts 的本地化字符串包；文档 8.2 未列出，属组装目录的必要补充）
shopt -s nullglob
for bundle in "${BIN_PATH}"/*.bundle; do
    echo "==> 复制资源包 $(basename "${bundle}")"
    cp -R "${bundle}" "${MACOS_DIR}/"
done
shopt -u nullglob

# 4. ad-hoc 签名（--deep 连同嵌套的资源包一并签名）
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> 校验签名"
codesign --verify --deep --strict "${APP_DIR}"

# 5. 输出产物路径
echo "==> 打包完成：${ROOT_DIR}/${APP_DIR}"
