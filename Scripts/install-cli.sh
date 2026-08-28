#!/usr/bin/env bash
set -euo pipefail

TARGET_LINK="${HOME}/.local/bin/lt"
UNINSTALL=0

if [[ "${1:-}" == "--uninstall" ]]; then
    UNINSTALL=1
fi

resolve_app_path() {
    if [[ -n "${LIGHTTRANS_APP_PATH:-}" ]]; then
        printf '%s\n' "${LIGHTTRANS_APP_PATH}"
        return
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ "$(basename "${script_dir}")" == "Resources" ]]; then
        printf '%s\n' "$(cd "${script_dir}/../.." && pwd)"
    else
        printf '%s\n' "/Applications/LightTrans.app"
    fi
}

APP_PATH="$(resolve_app_path)"
CLI_TARGET="${APP_PATH}/Contents/Helpers/lt"

if [[ "${UNINSTALL}" -eq 1 ]]; then
    if [[ -L "${TARGET_LINK}" ]]; then
        CURRENT_TARGET="$(readlink "${TARGET_LINK}")"
        if [[ "${CURRENT_TARGET}" == "${CLI_TARGET}" ]]; then
            rm "${TARGET_LINK}"
            echo "已移除 ${TARGET_LINK}"
            exit 0
        fi
    fi
    echo "未移除：${TARGET_LINK} 不是当前 LightTrans CLI 链接"
    exit 0
fi

if [[ ! -x "${CLI_TARGET}" ]]; then
    echo "错误：找不到 CLI 可执行文件 ${CLI_TARGET}" >&2
    exit 1
fi

mkdir -p "$(dirname "${TARGET_LINK}")"

if [[ -e "${TARGET_LINK}" || -L "${TARGET_LINK}" ]]; then
    if [[ -L "${TARGET_LINK}" ]]; then
        CURRENT_TARGET="$(readlink "${TARGET_LINK}")"
        if [[ "${CURRENT_TARGET}" == "${CLI_TARGET}" ]]; then
            echo "已安装：${TARGET_LINK}"
            exit 0
        fi
        echo "错误：${TARGET_LINK} 已存在且指向其他目标：${CURRENT_TARGET}" >&2
        exit 1
    fi
    echo "错误：${TARGET_LINK} 已存在且不是符号链接" >&2
    exit 1
fi

ln -s "${CLI_TARGET}" "${TARGET_LINK}"
echo "安装成功：${TARGET_LINK} -> ${CLI_TARGET}"
case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) echo "提示：当前 PATH 不含 ${HOME}/.local/bin，请自行添加到 shell 配置" ;;
esac
