#!/usr/bin/env bash
# 构建并安装 LightTrans；目标已存在时安全替换并重新启动。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="LightTrans"
BUNDLE_ID="com.andy.lighttrans"
SOURCE_APP="${ROOT_DIR}/build/${APP_NAME}.app"
INSTALL_DIR="${LIGHTTRANS_INSTALL_DIR:-/Applications}"
USE_SUDO=false

if [[ ! -d "${INSTALL_DIR}" ]]; then
    if ! mkdir -p "${INSTALL_DIR}" 2>/dev/null; then
        echo "==> 创建安装目录需要管理员权限"
        sudo -v
        USE_SUDO=true
        sudo mkdir -p "${INSTALL_DIR}"
    fi
fi

INSTALL_DIR="$(cd "${INSTALL_DIR}" && pwd -P)"
TARGET_APP="${INSTALL_DIR}/${APP_NAME}.app"
TARGET_EXECUTABLE="${TARGET_APP}/Contents/MacOS/${APP_NAME}"
STAGE_DIR=""
BACKUP_APP=""

run_privileged() {
    if [[ "${USE_SUDO}" == "true" ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

installed_pids() {
    ps -axo pid=,comm= | awk -v target="${TARGET_EXECUTABLE}" '
        {
            pid = $1
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
            if ($0 == target) print pid
        }
    '
}

wait_for_exit() {
    local attempts="$1"
    local index
    for ((index = 0; index < attempts; index++)); do
        if [[ -z "$(installed_pids)" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

signal_installed_pids() {
    local signal="$1"
    local pids="$2"
    local pid
    while IFS= read -r pid; do
        if [[ -n "${pid}" ]]; then
            kill "-${signal}" "${pid}" 2>/dev/null || true
        fi
    done <<< "${pids}"
}

stop_installed_app() {
    local pids
    pids="$(installed_pids)"
    if [[ -z "${pids}" ]]; then
        return
    fi

    echo "==> 正在退出已安装的 ${APP_NAME}"
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
    if wait_for_exit 50; then
        return
    fi

    pids="$(installed_pids)"
    signal_installed_pids TERM "${pids}"
    if wait_for_exit 20; then
        return
    fi

    pids="$(installed_pids)"
    signal_installed_pids KILL "${pids}"
    if ! wait_for_exit 20; then
        echo "错误：无法停止已安装的 ${APP_NAME}，未执行替换" >&2
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    trap - EXIT
    if [[ -n "${STAGE_DIR}" && -d "${STAGE_DIR}" ]]; then
        if [[ -n "${BACKUP_APP}" && -d "${BACKUP_APP}" && ! -e "${TARGET_APP}" ]]; then
            echo "==> 安装失败，正在恢复旧版本" >&2
            if ! run_privileged mv "${BACKUP_APP}" "${TARGET_APP}"; then
                echo "错误：旧版本自动恢复失败，备份保留在 ${BACKUP_APP}" >&2
                exit "${exit_code}"
            fi
        fi
        run_privileged rm -rf "${STAGE_DIR}" || true
    fi
    exit "${exit_code}"
}
trap cleanup EXIT

echo "==> 构建应用"
bash "${SCRIPT_DIR}/build-app.sh"
codesign --verify --deep --strict "${SOURCE_APP}"

stop_installed_app

if [[ ! -w "${INSTALL_DIR}" ]]; then
    echo "==> 安装目录需要管理员权限"
    sudo -v
    USE_SUDO=true
fi

STAGE_DIR="$(run_privileged mktemp -d "${INSTALL_DIR}/.${APP_NAME}-install.XXXXXX")"
STAGED_APP="${STAGE_DIR}/${APP_NAME}.app"
BACKUP_APP="${STAGE_DIR}/${APP_NAME}.previous.app"

echo "==> 复制并校验新版本"
run_privileged ditto "${SOURCE_APP}" "${STAGED_APP}"
codesign --verify --deep --strict "${STAGED_APP}"

ACTION="安装"
if [[ -e "${TARGET_APP}" ]]; then
    ACTION="更新"
    run_privileged mv "${TARGET_APP}" "${BACKUP_APP}"
fi

run_privileged mv "${STAGED_APP}" "${TARGET_APP}"
run_privileged xattr -dr com.apple.quarantine "${TARGET_APP}" 2>/dev/null || true
run_privileged touch "${TARGET_APP}"
run_privileged rm -rf "${BACKUP_APP}"
run_privileged rmdir "${STAGE_DIR}"
STAGE_DIR=""
BACKUP_APP=""

echo "==> ${ACTION}完成：${TARGET_APP}"
echo "==> 启动 ${APP_NAME}"
open -n "${TARGET_APP}"

for ((attempt = 0; attempt < 50; attempt++)); do
    if [[ -n "$(installed_pids)" ]]; then
        echo "==> ${APP_NAME} 已启动"
        exit 0
    fi
    sleep 0.1
done

echo "错误：应用已安装，但启动状态未确认，请手动打开 ${TARGET_APP}" >&2
exit 1
