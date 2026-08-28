#!/usr/bin/env bash
# 校验版本、构建应用并生成 GitHub 未签名预览版附件。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

RELEASE_TAG="${1:-}"
APP_NAME="LightTrans"
APP_PATH="build/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
CLI_PATH="${APP_PATH}/Contents/Helpers/lt"
CLI_INSTALL_SCRIPT_PATH="${APP_PATH}/Contents/Resources/install-cli.sh"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
EXPECTED_TAG="v${APP_VERSION}"
DIST_DIR="${LIGHTTRANS_DIST_DIR:-${ROOT_DIR}/dist}"
ASSET_NAME="${APP_NAME}-${EXPECTED_TAG}-macos-arm64.zip"
RELEASE_NOTES=".github/release-notes/${EXPECTED_TAG}.md"
KEYBOARD_SHORTCUTS_BUNDLE="KeyboardShortcuts_KeyboardShortcuts.bundle"

verify_resource_layout() {
    local app_path="$1"
    local expected_bundle="${app_path}/Contents/Resources/${KEYBOARD_SHORTCUTS_BUNDLE}"
    local cli_path="${app_path}/Contents/Helpers/lt"
    local install_cli_path="${app_path}/Contents/Resources/install-cli.sh"

    if [[ ! -f "${expected_bundle}/Info.plist" \
        || ! -f "${expected_bundle}/en.lproj/Localizable.strings" ]]; then
        echo "错误：${app_path} 缺少完整的 KeyboardShortcuts 资源包" >&2
        return 1
    fi
    if [[ -e "${app_path}/Contents/MacOS/${KEYBOARD_SHORTCUTS_BUNDLE}" ]]; then
        echo "错误：KeyboardShortcuts 资源包不得位于 Contents/MacOS" >&2
        return 1
    fi
    if [[ -e "${app_path}/${KEYBOARD_SHORTCUTS_BUNDLE}" ]]; then
        echo "错误：KeyboardShortcuts 资源包不得位于应用包根目录" >&2
        return 1
    fi
    if [[ ! -x "${cli_path}" ]]; then
        echo "错误：应用包缺少可执行 CLI ${cli_path}" >&2
        return 1
    fi
    if [[ ! -x "${install_cli_path}" ]]; then
        echo "错误：应用包缺少可执行的 install-cli.sh" >&2
        return 1
    fi
    bash -n "${install_cli_path}"
}

if [[ -z "${RELEASE_TAG}" ]]; then
    echo "用法：bash Scripts/package-release.sh v{版本}" >&2
    exit 1
fi
if [[ "${RELEASE_TAG}" != "${EXPECTED_TAG}" ]]; then
    echo "错误：Tag ${RELEASE_TAG} 与应用版本 ${APP_VERSION} 不一致" >&2
    exit 1
fi
if [[ ! -f "${RELEASE_NOTES}" ]]; then
    echo "错误：找不到发布说明 ${RELEASE_NOTES}" >&2
    exit 1
fi
if [[ -e "${DIST_DIR}" ]]; then
    echo "错误：输出目录已存在，请更换 LIGHTTRANS_DIST_DIR：${DIST_DIR}" >&2
    exit 1
fi

bash "${SCRIPT_DIR}/build-app.sh"
verify_resource_layout "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"
codesign --verify --strict "${CLI_PATH}"

ACTUAL_ARCHS="$(lipo -archs "${EXECUTABLE_PATH}")"
if [[ "${ACTUAL_ARCHS}" != "arm64" ]]; then
    echo "错误：预览版必须只包含 arm64，实际为 ${ACTUAL_ARCHS}" >&2
    exit 1
fi
CLI_ARCHS="$(lipo -archs "${CLI_PATH}")"
if [[ "${CLI_ARCHS}" != "arm64" ]]; then
    echo "错误：CLI 必须只包含 arm64，实际为 ${CLI_ARCHS}" >&2
    exit 1
fi
if otool -L "${CLI_PATH}" | rg -q '\.build|/Sources/'; then
    echo "错误：CLI 运行时依赖指向源码目录" >&2
    exit 1
fi
CLI_VERSION="$("${CLI_PATH}" --version)"
if [[ "${CLI_VERSION}" != "${APP_VERSION}" ]]; then
    echo "错误：CLI 版本 ${CLI_VERSION} 与 App 版本 ${APP_VERSION} 不一致" >&2
    exit 1
fi
"${CLI_PATH}" --help >/dev/null

mkdir -p "${DIST_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${DIST_DIR}/${ASSET_NAME}"
(
    cd "${DIST_DIR}"
    shasum -a 256 "${ASSET_NAME}" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

VERIFY_DIR="$(mktemp -d)"
ditto -x -k "${DIST_DIR}/${ASSET_NAME}" "${VERIFY_DIR}"
verify_resource_layout "${VERIFY_DIR}/${APP_NAME}.app"
codesign --verify --deep --strict "${VERIFY_DIR}/${APP_NAME}.app"
codesign --verify --strict "${VERIFY_DIR}/${APP_NAME}.app/Contents/Helpers/lt"

UNPACKED_ARCHS="$(lipo -archs "${VERIFY_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}")"
if [[ "${UNPACKED_ARCHS}" != "arm64" ]]; then
    echo "错误：解压后的预览版架构异常：${UNPACKED_ARCHS}" >&2
    exit 1
fi
UNPACKED_CLI_ARCHS="$(lipo -archs "${VERIFY_DIR}/${APP_NAME}.app/Contents/Helpers/lt")"
if [[ "${UNPACKED_CLI_ARCHS}" != "arm64" ]]; then
    echo "错误：解压后的 CLI 架构异常：${UNPACKED_CLI_ARCHS}" >&2
    exit 1
fi

echo "==> Release 附件已生成"
echo "${DIST_DIR}/${ASSET_NAME}"
echo "${DIST_DIR}/SHA256SUMS"
