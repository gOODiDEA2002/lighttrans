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
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
EXPECTED_TAG="v${APP_VERSION}"
DIST_DIR="${LIGHTTRANS_DIST_DIR:-${ROOT_DIR}/dist}"
ASSET_NAME="${APP_NAME}-${EXPECTED_TAG}-macos-arm64.zip"
RELEASE_NOTES=".github/release-notes/${EXPECTED_TAG}.md"

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
codesign --verify --deep --strict "${APP_PATH}"

ACTUAL_ARCHS="$(lipo -archs "${EXECUTABLE_PATH}")"
if [[ "${ACTUAL_ARCHS}" != "arm64" ]]; then
    echo "错误：预览版必须只包含 arm64，实际为 ${ACTUAL_ARCHS}" >&2
    exit 1
fi

mkdir -p "${DIST_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${DIST_DIR}/${ASSET_NAME}"
(
    cd "${DIST_DIR}"
    shasum -a 256 "${ASSET_NAME}" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

VERIFY_DIR="$(mktemp -d)"
ditto -x -k "${DIST_DIR}/${ASSET_NAME}" "${VERIFY_DIR}"
codesign --verify --deep --strict "${VERIFY_DIR}/${APP_NAME}.app"

UNPACKED_ARCHS="$(lipo -archs "${VERIFY_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}")"
if [[ "${UNPACKED_ARCHS}" != "arm64" ]]; then
    echo "错误：解压后的预览版架构异常：${UNPACKED_ARCHS}" >&2
    exit 1
fi

echo "==> Release 附件已生成"
echo "${DIST_DIR}/${ASSET_NAME}"
echo "${DIST_DIR}/SHA256SUMS"
