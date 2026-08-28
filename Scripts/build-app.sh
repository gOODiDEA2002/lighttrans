#!/usr/bin/env bash
# 构建并打包 LightTrans.app（ad-hoc 本地签名，仅本机使用）
# 依据详细设计第 8 节。任何一步失败立即退出。
set -euo pipefail

# 切到工程根目录（脚本位于 Scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

APP_NAME="LightTrans"
CLI_NAME="lt"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_PATH="Resources/AppIcon.icns"
CLI_INSTALL_SCRIPT="Scripts/install-cli.sh"
KEYBOARD_SHORTCUTS_CHECKOUT=".build/checkouts/KeyboardShortcuts"
KEYBOARD_SHORTCUTS_RECORDER="${KEYBOARD_SHORTCUTS_CHECKOUT}/Sources/KeyboardShortcuts/Recorder.swift"
KEYBOARD_SHORTCUTS_UTILITIES="${KEYBOARD_SHORTCUTS_CHECKOUT}/Sources/KeyboardShortcuts/Utilities.swift"
KEYBOARD_SHORTCUTS_PREVIEW_PATCH="${ROOT_DIR}/Patches/KeyboardShortcuts-2.4.0-remove-previews.patch"
KEYBOARD_SHORTCUTS_RESOURCES_PATCH="${ROOT_DIR}/Patches/KeyboardShortcuts-2.4.0-app-resources.patch"
EXPECTED_KEYBOARD_SHORTCUTS_REVISION="1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27"
EXPECTED_KEYBOARD_SHORTCUTS_BUNDLE="KeyboardShortcuts_KeyboardShortcuts.bundle"

if [[ ! -f "${ICON_PATH}" ]]; then
    echo "错误：找不到应用图标 ${ICON_PATH}，请先运行 bash Scripts/generate-app-icon.sh" >&2
    exit 1
fi

# KeyboardShortcuts 2.4.0 含三个只供 Xcode 使用的 SwiftUI #Preview。
# 目标机器可能只有 Command Line Tools，构建前删除这些预览代码，运行时代码不变。
echo "==> 解析 Swift Package 依赖"
swift package resolve
if [[ ! -f "${KEYBOARD_SHORTCUTS_RECORDER}" || ! -f "${KEYBOARD_SHORTCUTS_UTILITIES}" \
    || ! -f "${KEYBOARD_SHORTCUTS_PREVIEW_PATCH}" || ! -f "${KEYBOARD_SHORTCUTS_RESOURCES_PATCH}" ]]; then
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
    git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" apply --check "${KEYBOARD_SHORTCUTS_PREVIEW_PATCH}"
    git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" apply "${KEYBOARD_SHORTCUTS_PREVIEW_PATCH}"
fi
if grep -q '^[[:space:]]*#Preview' "${KEYBOARD_SHORTCUTS_RECORDER}"; then
    echo "错误：KeyboardShortcuts 预览代码未成功移除" >&2
    exit 1
fi

# SwiftPM 的命令行可执行目标把 Bundle.module 的首选位置生成为 .app 根目录，
# 但 macOS 严格签名不允许在 bundle 根目录放资源。应用包内改从标准 Resources 目录加载，
# 直接运行 SwiftPM 产物和单元测试时仍回退到原有 Bundle.module。
if grep -q 'NSLocalizedString(self, bundle: \.module, comment: self)' "${KEYBOARD_SHORTCUTS_UTILITIES}"; then
    echo "==> 调整 KeyboardShortcuts 的应用资源定位"
    git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" apply --unidiff-zero --check "${KEYBOARD_SHORTCUTS_RESOURCES_PATCH}"
    git -C "${KEYBOARD_SHORTCUTS_CHECKOUT}" apply --unidiff-zero "${KEYBOARD_SHORTCUTS_RESOURCES_PATCH}"
fi
if ! grep -q 'NSLocalizedString(self, bundle: \.keyboardShortcutsResources, comment: self)' "${KEYBOARD_SHORTCUTS_UTILITIES}"; then
    echo "错误：KeyboardShortcuts 资源定位补丁未成功应用" >&2
    exit 1
fi

# 1. release 构建
echo "==> swift build -c release --product ${APP_NAME}"
swift build -c release --product "${APP_NAME}"
echo "==> swift build -c release --product ${CLI_NAME}"
swift build -c release --product "${CLI_NAME}"
BIN_PATH="$(swift build -c release --show-bin-path)"

# 2. 组装 .app 目录结构（先清理旧产物）
echo "==> 组装 ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
mkdir -p "${HELPERS_DIR}"

# 3. 复制可执行文件与 Info.plist
cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${BIN_PATH}/${CLI_NAME}" "${HELPERS_DIR}/${CLI_NAME}"
chmod 755 "${HELPERS_DIR}/${CLI_NAME}"
cp "Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ICON_PATH}" "${RESOURCES_DIR}/AppIcon.icns"
cp "${CLI_INSTALL_SCRIPT}" "${RESOURCES_DIR}/install-cli.sh"
chmod 755 "${RESOURCES_DIR}/install-cli.sh"
if [[ ! -x "${HELPERS_DIR}/${CLI_NAME}" || ! -x "${RESOURCES_DIR}/install-cli.sh" ]]; then
    echo "错误：CLI 或安装脚本缺少可执行权限" >&2
    exit 1
fi

# 3.1 复制依赖生成的资源包（.bundle）到标准应用资源目录
shopt -s nullglob
for bundle in "${BIN_PATH}"/*.bundle; do
    echo "==> 复制资源包 $(basename "${bundle}")"
    cp -R "${bundle}" "${RESOURCES_DIR}/"
done
shopt -u nullglob
if [[ ! -f "${RESOURCES_DIR}/${EXPECTED_KEYBOARD_SHORTCUTS_BUNDLE}/en.lproj/Localizable.strings" ]]; then
    echo "错误：应用包缺少 KeyboardShortcuts 本地化资源" >&2
    exit 1
fi

# 4. 先签名 CLI，再签名 App
echo "==> 签名 ${CLI_NAME}"
codesign --force --sign - "${HELPERS_DIR}/${CLI_NAME}"

# 5. ad-hoc 签名（--deep 连同嵌套的资源包一并签名）
echo "==> codesign (ad-hoc)"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> 校验签名"
codesign --verify --strict "${HELPERS_DIR}/${CLI_NAME}"
codesign --verify --deep --strict "${APP_DIR}"

echo "==> 校验架构"
if [[ "$(lipo -archs "${MACOS_DIR}/${APP_NAME}")" != "arm64" ]]; then
    echo "错误：${APP_NAME} 必须为 arm64" >&2
    exit 1
fi
if [[ "$(lipo -archs "${HELPERS_DIR}/${CLI_NAME}")" != "arm64" ]]; then
    echo "错误：${CLI_NAME} 必须为 arm64" >&2
    exit 1
fi

echo "==> 校验 CLI 运行时依赖"
if otool -L "${HELPERS_DIR}/${CLI_NAME}" | rg -q '\.build|/Sources/'; then
    echo "错误：CLI 存在源码目录运行时依赖" >&2
    exit 1
fi

echo "==> 校验 CLI 版本"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${CONTENTS_DIR}/Info.plist")"
CLI_VERSION="$("${HELPERS_DIR}/${CLI_NAME}" --version)"
if [[ "${CLI_VERSION}" != "${APP_VERSION}" ]]; then
    echo "错误：CLI 版本 ${CLI_VERSION} 与 App 版本 ${APP_VERSION} 不一致" >&2
    exit 1
fi

# 6. 输出产物路径
echo "==> 打包完成：${ROOT_DIR}/${APP_DIR}"
