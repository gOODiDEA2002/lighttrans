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

# 5. 输出产物路径
echo "==> 打包完成：${ROOT_DIR}/${APP_DIR}"
