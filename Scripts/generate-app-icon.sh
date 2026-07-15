#!/usr/bin/env bash
# 从 1024 x 1024 PNG 源图生成 macOS 使用的 ICNS 图标。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

SOURCE_ICON="${1:-Resources/AppIcon.png}"
OUTPUT_ICON="${2:-Resources/AppIcon.icns}"

if [[ ! -f "${SOURCE_ICON}" ]]; then
    echo "错误：找不到图标源文件 ${SOURCE_ICON}" >&2
    exit 1
fi

WIDTH="$(sips -g pixelWidth "${SOURCE_ICON}" | awk '/pixelWidth/ { print $2 }')"
HEIGHT="$(sips -g pixelHeight "${SOURCE_ICON}" | awk '/pixelHeight/ { print $2 }')"
HAS_ALPHA="$(sips -g hasAlpha "${SOURCE_ICON}" | awk '/hasAlpha/ { print $2 }')"
if [[ "${WIDTH}" != "1024" || "${HEIGHT}" != "1024" ]]; then
    echo "错误：图标源文件必须为 1024 x 1024，当前为 ${WIDTH} x ${HEIGHT}" >&2
    exit 1
fi

if [[ "${HAS_ALPHA}" != "yes" ]]; then
    echo "错误：图标源文件必须包含透明圆角" >&2
    exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lighttrans-icon.XXXXXX")"
ICONSET_DIR="${TEMP_DIR}/AppIcon.iconset"
trap 'rm -rf "${TEMP_DIR}"' EXIT
mkdir -p "${ICONSET_DIR}" "$(dirname "${OUTPUT_ICON}")"

resize_icon() {
    local size="$1"
    local filename="$2"
    sips -z "${size}" "${size}" "${SOURCE_ICON}" \
        --out "${ICONSET_DIR}/${filename}" >/dev/null
}

resize_icon 16 icon_16x16.png
resize_icon 32 icon_16x16@2x.png
resize_icon 32 icon_32x32.png
resize_icon 64 icon_32x32@2x.png
resize_icon 128 icon_128x128.png
resize_icon 256 icon_128x128@2x.png
resize_icon 256 icon_256x256.png
resize_icon 512 icon_256x256@2x.png
resize_icon 512 icon_512x512.png
resize_icon 1024 icon_512x512@2x.png

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICON}"
echo "图标已生成：${ROOT_DIR}/${OUTPUT_ICON}"
