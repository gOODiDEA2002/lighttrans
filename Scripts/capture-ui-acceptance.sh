#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

OUT_DIR="build/ui-acceptance"
MENUBAR_DIR="${OUT_DIR}/menubar"
OVERLAY_DIR="${OUT_DIR}/overlays"
MENUBAR_ONLY=0
if [[ "${1:-}" == "--menubar-only" ]]; then
    MENUBAR_ONLY=1
fi
mkdir -p "${OUT_DIR}" "${MENUBAR_DIR}" "${OVERLAY_DIR}"
: > "${OUT_DIR}/state-mapping.txt"

echo "==> swift build (Debug)"
swift build
BIN_PATH="$(swift build --show-bin-path)/LightTrans"

if [[ ! -x "${BIN_PATH}" ]]; then
    echo "错误：未找到可执行文件 ${BIN_PATH}" >&2
    exit 1
fi

STATES=(
    panel-idle
    panel-streaming
    panel-done
    panel-partial-fail
    panel-stopped
    panel-height-70
    panel-height-100
    panel-height-240
    settings-api-idle
    settings-api-testing
    settings-api-success
    settings-api-long-error
    settings-templates-valid
    settings-templates-invalid
    history-normal
    history-search-hit
    history-no-match
    history-no-records
    history-long-device-model
)

expected_size_for_state() {
    local state="$1"
    case "${state}" in
        panel-*)
            echo "1120 1200"
            ;;
        settings-*)
            echo "1040 900"
            ;;
        history-*)
            echo "1360 960"
            ;;
        *)
            echo "未知状态: ${state}" >&2
            return 1
            ;;
    esac
}

window_info_for_pid() {
    local pid="$1"
    local expected_w="$2"
    local expected_h="$3"
    swift - "${pid}" "${expected_w}" "${expected_h}" <<'SWIFT'
import Foundation
import CoreGraphics

let pid = Int(CommandLine.arguments[1]) ?? -1
let expectedW = Int(CommandLine.arguments[2]) ?? 0
let expectedH = Int(CommandLine.arguments[3]) ?? 0
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

var bestWindow: (id: Int, width: Int, height: Int, score: Int)?
for item in list {
    guard let owner = item[kCGWindowOwnerPID as String] as? Int, owner == pid else { continue }
    guard let windowID = item[kCGWindowNumber as String] as? Int else { continue }
    let alpha = item[kCGWindowAlpha as String] as? Double ?? 1
    if alpha <= 0 { continue }
    let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = Int((bounds["Width"] as? Double) ?? 0)
    let height = Int((bounds["Height"] as? Double) ?? 0)
    if width <= 0 || height <= 0 { continue }
    let score = abs(width - expectedW) + abs(height - expectedH)
    if bestWindow == nil || score < bestWindow!.score {
        bestWindow = (id: windowID, width: width, height: height, score: score)
    }
}

if let window = bestWindow {
    print("\(window.id) \(window.width) \(window.height)")
    exit(0)
}
exit(1)
SWIFT
}
expected_frame_for_state() {
    local state="$1"
    case "${state}" in
        panel-*)
            echo "560 600"
            ;;
        settings-*)
            echo "520 450"
            ;;
        history-*)
            echo "680 480"
            ;;
        *)
            echo "未知状态: ${state}" >&2
            return 1
            ;;
    esac
}


read_image_size() {
    local file="$1"
    local meta
    meta="$(sips -g pixelWidth -g pixelHeight "${file}" 2>/dev/null)"
    local width
    local height
    width="$(echo "${meta}" | awk '/pixelWidth:/ {print $2}')"
    height="$(echo "${meta}" | awk '/pixelHeight:/ {print $2}')"
    echo "${width} ${height}"
}

image_hash() {
    local file="$1"
    shasum -a 256 "${file}" | awk '{print $1}'
}

is_frontmost_pid() {
    local pid="$1"
    local front_pid
    front_pid="$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true' 2>/dev/null || echo "")"
    [[ "${front_pid}" == "${pid}" ]]
}

wait_for_state_env_gate() {
    local state="$1"
    local state_log="$2"
    local mode="$3" # panel | standard
    local ok=0

    for _ in {1..180}; do
        if [[ "${mode}" == "panel" ]]; then
            if rg -q "UI_ACCEPTANCE_ENV state=${state} appearance=NSAppearanceNameDarkAqua scale=2\\.0" "${state_log}" 2>/dev/null; then
                ok=1
                break
            fi
        else
            if rg -q "UI_ACCEPTANCE_ENV state=${state} appearance=NSAppearanceNameDarkAqua scale=2\\.0 .*main=true .*active=true" "${state_log}" 2>/dev/null; then
                ok=1
                break
            fi
        fi
        sleep 0.1
    done

    if [[ "${ok}" -ne 1 ]]; then
        if [[ "${mode}" == "panel" ]]; then
            echo "错误：状态 ${state} 截图前未通过 dark+2x 门禁，详见 ${state_log}" >&2
        else
            echo "错误：状态 ${state} 截图前未通过激活门禁（dark+2x+main/active），详见 ${state_log}" >&2
        fi
        return 1
    fi
}

require_ffmpeg() {
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "错误：未安装 ffmpeg，无法生成 50% overlay。请安装后重试或改走 manual-required。" >&2
        exit 2
    fi
}

set_system_dark_mode() {
    local dark_value="$1"
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to ${dark_value}" >/dev/null 2>&1
}

current_system_dark_mode() {
    osascript -e "tell application \"System Events\" to tell appearance preferences to get dark mode" 2>/dev/null || echo "unknown"
}

extract_menubar_ready() {
    local logfile="$1"
    python3 - "$logfile" <<'PY'
import re
import sys
text = open(sys.argv[1], 'r', encoding='utf-8', errors='ignore').read()
m = re.search(r'UI_ACCEPTANCE_MENUBAR_READY state=(\w+) appearance=([^\s]+)', text)
if not m:
    sys.exit(1)
print(" ".join(m.groups()))
PY
}

menubar_window_for_pid() {
    local pid="$1"
    swift - "${pid}" <<'SWIFT'
import Foundation
import CoreGraphics

struct Candidate {
    let id: Int
    let layer: Int
    let name: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
    let alpha: Double
    let onscreen: Int
    var area: Int { w * h }
    var isItem0: Bool { name == "Item-0" }
    var xNonNegative: Bool { x >= 0 }
}

let pid = Int(CommandLine.arguments[1]) ?? -1
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

var all: [Candidate] = []
for item in list {
    guard let owner = item[kCGWindowOwnerPID as String] as? Int, owner == pid else { continue }
    let layer = item[kCGWindowLayer as String] as? Int ?? -1
    guard layer == 25 else { continue }
    let alpha = item[kCGWindowAlpha as String] as? Double ?? 1
    guard alpha > 0 else { continue }
    let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = Int((bounds["X"] as? Double) ?? 0)
    let y = Int((bounds["Y"] as? Double) ?? 0)
    let w = Int((bounds["Width"] as? Double) ?? 0)
    let h = Int((bounds["Height"] as? Double) ?? 0)
    guard w > 0, h > 0 else { continue }
    let name = item[kCGWindowName as String] as? String ?? ""
    let id = item[kCGWindowNumber as String] as? Int ?? -1
    let onscreen = item[kCGWindowIsOnscreen as String] as? Int ?? 0
    all.append(Candidate(id: id, layer: layer, name: name, x: x, y: y, w: w, h: h, alpha: alpha, onscreen: onscreen))
}

func rank(_ c: Candidate) -> (Int, Int, Int, Int) {
    let scoreItem = c.isItem0 ? 1 : 0
    let scoreOnscreen = c.onscreen == 1 ? 1 : 0
    let scoreX = c.xNonNegative ? 1 : 0
    return (scoreItem, scoreOnscreen, scoreX, c.x)
}

let item0Pool = all.filter { $0.isItem0 }
let fallbackPool = all.filter {
    $0.w >= 20 && $0.w <= 100 && $0.h >= 20 && $0.h <= 40
}
let pool = item0Pool.isEmpty ? fallbackPool : item0Pool
guard let best = pool.sorted(by: { a, b in
    let ra = rank(a), rb = rank(b)
    if ra.0 != rb.0 { return ra.0 > rb.0 }
    if ra.1 != rb.1 { return ra.1 > rb.1 }
    if ra.2 != rb.2 { return ra.2 > rb.2 }
    if ra.3 != rb.3 { return ra.3 > rb.3 }
    return a.area > b.area
}).first else {
    exit(1)
}

let safeName = best.name.replacingOccurrences(of: " ", with: "_")
print("\(best.id)\t\(best.x)\t\(best.y)\t\(best.w)\t\(best.h)\t\(best.layer)\t\(safeName)\t\(best.alpha)\t\(best.onscreen)")
SWIFT
}

mouse_event() {
    local kind="$1"
    local x="$2"
    local y="$3"
    swift - "$kind" "$x" "$y" <<'SWIFT'
import Foundation
import CoreGraphics

let kind = CommandLine.arguments[1]
let x = Double(CommandLine.arguments[2]) ?? 0
let y = Double(CommandLine.arguments[3]) ?? 0
let point = CGPoint(x: x, y: y)
let type: CGEventType = (kind == "down") ? .leftMouseDown : .leftMouseUp
guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
    exit(1)
}
event.post(tap: .cghidEventTap)
SWIFT
}

capture_menubar_live() {
    local state="$1"
    local png_path="$2"
    local log_path="$3"

    "${BIN_PATH}" --ui-acceptance-menubar-state "${state}" >"${log_path}" 2>&1 &
    local app_pid=$!
    trap 'kill "${app_pid}" 2>/dev/null || true' EXIT

    local ready_line=""
    for _ in {1..100}; do
        if ready_line="$(extract_menubar_ready "${log_path}" 2>/dev/null)"; then
            break
        fi
        sleep 0.1
    done
    if [[ -z "${ready_line}" ]]; then
        echo "错误：菜单栏 ${state} 未输出 ready 日志，详见 ${log_path}" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    local parsed_state appearance
    read -r parsed_state appearance <<<"${ready_line}"

    local window_line=""
    for _ in {1..120}; do
        if window_line="$(menubar_window_for_pid "${app_pid}" 2>/dev/null)"; then
            break
        fi
        sleep 0.1
    done
    if [[ -z "${window_line}" ]]; then
        echo "错误：菜单栏 ${state} 未在 WindowServer 发现状态项窗口（pid=${app_pid}）" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    local window_id x y w h layer window_name alpha onscreen
    IFS=$'\t' read -r window_id x y w h layer window_name alpha onscreen <<<"${window_line}"

    if [[ "${x}" -lt 0 || "${y}" -lt 0 ]]; then
        echo "错误：菜单栏 ${state} bounds 非法（x/y 负值）：${window_line}" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi
    if [[ "${y}" -gt 40 ]]; then
        echo "错误：菜单栏 ${state} bounds.y=${y} 不在菜单栏区域" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    if [[ "${state}" == "pressed" ]]; then
        local center_x center_y
        center_x=$((x + w / 2))
        center_y=$((y + h / 2))
        mouse_event down "${center_x}" "${center_y}"
        sleep 0.20
        screencapture -x -R "${x},${y},${w},${h}" "${png_path}"
        mouse_event up "${center_x}" "${center_y}"
        sleep 0.10
    else
        screencapture -x -R "${x},${y},${w},${h}" "${png_path}"
    fi

    if ! kill -0 "${app_pid}" 2>/dev/null; then
        echo "错误：菜单栏 ${state} 截图后进程已退出（疑似崩溃），详见 ${log_path}" >&2
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi
    if rg -q "(Fatal error|SIGABRT|SIGSEGV|Illegal instruction|Trace/BPT trap|EXC_BAD_ACCESS)" "${log_path}"; then
        echo "错误：菜单栏 ${state} 日志包含崩溃信号，详见 ${log_path}" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    read -r img_w img_h < <(read_image_size "${png_path}")
    local expected_img_w=$((w * 2))
    local expected_img_h=$((h * 2))
    if [[ "${img_w}" != "${expected_img_w}" || "${img_h}" != "${expected_img_h}" ]]; then
        echo "错误：菜单栏 ${state} PNG 像素尺寸不符，期望 ${expected_img_w}x${expected_img_h}，实际 ${img_w}x${img_h}" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi
    local hash_value
    hash_value="$(image_hash "${png_path}")"

    printf "state=%s pid=%s window_id=%s layer=%s name=%s bounds=(x:%s,y:%s,w:%s,h:%s) alpha=%s onscreen=%s appearance=%s image=%sx%s hash=%s png=%s\n" \
        "${state}" "${app_pid}" "${window_id}" "${layer}" "${window_name}" "${x}" "${y}" "${w}" "${h}" "${alpha}" "${onscreen}" "${appearance}" "${img_w}" "${img_h}" "${hash_value}" "${png_path}" \
        > "${png_path%.png}.meta.txt"

    kill "${app_pid}" 2>/dev/null || true
    wait "${app_pid}" 2>/dev/null || true
    trap - EXIT
}

generate_overlays() {
    require_ffmpeg
    local pairs=(
        "panel-idle|docs/assets/v5/lighttrans_panel_idle.png"
        "panel-streaming|docs/assets/v5/lighttrans_panel_streaming.png"
        "panel-done|docs/assets/v5/lighttrans_panel_done.png"
        "panel-partial-fail|docs/assets/v5/lighttrans_panel_partial_fail.png"
        "panel-stopped|docs/assets/v5/lighttrans_panel_stopped.png"
        "settings-api-success|docs/assets/v5/lighttrans_settings_api.png"
        "settings-templates-valid|docs/assets/v5/lighttrans_settings_templates.png"
        "history-search-hit|docs/assets/v5/lighttrans_history.png"
    )

    : > "${OVERLAY_DIR}/overlay-mapping.txt"
    for pair in "${pairs[@]}"; do
        local state="${pair%%|*}"
        local baseline="${pair##*|}"
        local actual="${OUT_DIR}/${state}.png"
        local out="${OVERLAY_DIR}/${state}-overlay.png"
        ffmpeg -y -i "${baseline}" -i "${actual}" -filter_complex "[0][1]blend=all_mode=normal:all_opacity=0.5" -frames:v 1 "${out}" >/dev/null 2>&1
        printf "%s|baseline=%s|actual=%s|overlay=%s\n" "${state}" "${baseline}" "${actual}" "${out}" >> "${OVERLAY_DIR}/overlay-mapping.txt"
    done
}

if [[ "${MENUBAR_ONLY}" -ne 1 ]]; then
for state in "${STATES[@]}"; do
    echo "==> capture ${state}"
    read -r expected_w expected_h < <(expected_size_for_state "${state}")
    read -r expected_frame_w expected_frame_h < <(expected_frame_for_state "${state}")
    out_file="${OUT_DIR}/${state}.png"

    state_log="/tmp/lighttrans-ui-acceptance-${state}.log"
    "${BIN_PATH}" --ui-acceptance-state "${state}" >"${state_log}" 2>&1 &
    app_pid=$!

    trap 'kill "${app_pid}" 2>/dev/null || true' EXIT

    window_info=""
    for _ in {1..80}; do
        if window_info="$(window_info_for_pid "${app_pid}" "${expected_frame_w}" "${expected_frame_h}" 2>/dev/null)"; then
            break
        fi
        sleep 0.1
    done

    if [[ -z "${window_info}" ]]; then
        echo "错误：状态 ${state} 未找到可截图窗口（pid=${app_pid}）" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    read -r window_id window_w window_h <<<"${window_info}"
    if [[ "${state}" == settings-* || "${state}" == history-* ]]; then
        osascript -e "tell application \"System Events\" to set frontmost of the first process whose unix id is ${app_pid} to true" >/dev/null 2>&1 || true
    fi
    if [[ "${window_w}" != "${expected_frame_w}" || "${window_h}" != "${expected_frame_h}" ]]; then
        echo "错误：状态 ${state} 窗口 frame 不符，期望 ${expected_frame_w}x${expected_frame_h}，实际 ${window_w}x${window_h}" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    if [[ "${state}" == panel-* ]]; then
        if ! wait_for_state_env_gate "${state}" "${state_log}" "panel"; then
            kill "${app_pid}" 2>/dev/null || true
            wait "${app_pid}" 2>/dev/null || true
            exit 1
        fi
    else
        if ! wait_for_state_env_gate "${state}" "${state_log}" "standard"; then
            kill "${app_pid}" 2>/dev/null || true
            wait "${app_pid}" 2>/dev/null || true
            exit 1
        fi
    fi

    screencapture -x -o -l "${window_id}" "${out_file}"
    read -r image_w image_h < <(read_image_size "${out_file}")
    if [[ "${image_w}" != "${expected_w}" || "${image_h}" != "${expected_h}" ]]; then
        echo "错误：状态 ${state} 截图尺寸不符，期望 ${expected_w}x${expected_h}，实际 ${image_w}x${image_h}" >&2
        kill "${app_pid}" 2>/dev/null || true
        wait "${app_pid}" 2>/dev/null || true
        exit 1
    fi

    post_frontmost="n/a"
    if [[ "${state}" == settings-* || "${state}" == history-* ]]; then
        if is_frontmost_pid "${app_pid}"; then
            post_frontmost="true"
        else
            post_frontmost="false"
            echo "错误：状态 ${state} 截图后前台进程校验失败（可能被抢焦）" >&2
            kill "${app_pid}" 2>/dev/null || true
            wait "${app_pid}" 2>/dev/null || true
            exit 1
        fi
    fi

    printf "%s|frame=%sx%s|image=%sx%s|post_frontmost=%s|log=%s\n" \
        "${state}" "${window_w}" "${window_h}" "${image_w}" "${image_h}" "${post_frontmost}" "${state_log}" \
        >> "${OUT_DIR}/state-mapping.txt"

    kill "${app_pid}" 2>/dev/null || true
    wait "${app_pid}" 2>/dev/null || true
    trap - EXIT
done
fi

ORIGINAL_DARK_MODE="$(current_system_dark_mode)"
if ! set_system_dark_mode true; then
    echo "错误：无法自动切换到深色模式，菜单栏证据无法继续" >&2
    exit 1
fi
sleep 1
echo "==> capture menubar dark (live status item window)"
capture_menubar_live dark "${MENUBAR_DIR}/menubar-dark.png" "${MENUBAR_DIR}/menubar-dark.log"

if ! set_system_dark_mode false; then
    echo "错误：无法自动切换到浅色模式，菜单栏证据无法继续" >&2
    exit 1
fi
sleep 1
echo "==> capture menubar light (live status item window)"
capture_menubar_live light "${MENUBAR_DIR}/menubar-light.png" "${MENUBAR_DIR}/menubar-light.log"

if ! set_system_dark_mode true; then
    echo "错误：无法切回深色以采集 pressed 状态" >&2
    exit 1
fi
sleep 1
echo "==> capture menubar pressed (CGEvent mouseDown hold)"
capture_menubar_live pressed "${MENUBAR_DIR}/menubar-pressed.png" "${MENUBAR_DIR}/menubar-pressed.log"

dark_hash="$(image_hash "${MENUBAR_DIR}/menubar-dark.png")"
light_hash="$(image_hash "${MENUBAR_DIR}/menubar-light.png")"
pressed_hash="$(image_hash "${MENUBAR_DIR}/menubar-pressed.png")"
if [[ "${dark_hash}" == "${light_hash}" || "${dark_hash}" == "${pressed_hash}" || "${light_hash}" == "${pressed_hash}" ]]; then
    echo "错误：菜单栏三态 hash 存在重复（dark=${dark_hash}, light=${light_hash}, pressed=${pressed_hash}）" >&2
    exit 1
fi

cat > "${MENUBAR_DIR}/manual-required-pressed.md" <<'EOF'
# manual-required: menubar-pressed

- 触发条件：仅当自动采集失败（未生成 `menubar-pressed.png`，或 hash 校验失败）时启用人工回退。
- 手工步骤：
  1. 运行 Debug 构建应用，确认状态栏图标已出现。
  2. 在深色模式下按住状态栏图标（保持 pressed 高亮）时，使用系统截图捕获图标区域。
  3. 将截图保存为 `build/ui-acceptance/menubar/menubar-pressed-manual.png`。
  4. 在该目录补充 `menubar-pressed-manual-note.txt`，记录采集时间与采集人。
- 说明：若自动证据已成功并通过三态 hash 互异校验，可直接使用自动证据，不需要人工回退。
EOF

if [[ "${ORIGINAL_DARK_MODE}" == "true" || "${ORIGINAL_DARK_MODE}" == "false" ]]; then
    set_system_dark_mode "${ORIGINAL_DARK_MODE}" || true
fi

if [[ "${MENUBAR_ONLY}" -ne 1 ]]; then
    generate_overlays
fi

echo "==> 完成：${OUT_DIR}"
echo "==> 说明：菜单栏 pressed 仅在自动采集失败时走 manual 回退（见 ${MENUBAR_DIR}/manual-required-pressed.md）"
