#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – forge-tui TUI backend
# Drop-in replacement for gum.sh – same function signatures.
# Requires: forge-tui (Rust binary)

: "${VFF_COLOR_TITLE:=212}"
: "${VFF_COLOR_ACCENT:=34}"
: "${VFF_COLOR_ERROR:=196}"
: "${VFF_COLOR_SUCCESS:=34}"

FORGE_TUI="${FORGE_TUI:-forge-tui}"
FORGE_TUI_SOCKET="${FORGE_TUI_SOCKET:-/tmp/forge-tui.sock}"
FORGE_TUI_DAEMON="${FORGE_TUI_DAEMON:-}"

_theme_ansi_code() { printf '38;5;%s' "${1:-212}"; }
_theme_ansi()      { printf '\e[%sm' "$(_theme_ansi_code "${1:-212}")"; }

_forge() {
    local _dir _tmp _out
    _dir=$(mktemp -d --tmpdir vff-tui-XXXXXX)
    chmod 700 "$_dir"
    _tmp="$_dir/input.json"
    _out="$_dir/output.json"
    printf '%s\n' "$1" > "$_tmp"
    "$FORGE_TUI" --mode widget --input "$_tmp" --output "$_out" < /dev/tty > /dev/tty 2>/dev/null
    cat "$_out" 2>/dev/null
}

_forge_result() {
    local _json
    _json=$(_forge "$1")
    jq -r 'if .result | type == "array" then .result[] else .result // .selected // empty end' <<< "$_json" 2>/dev/null
}

_forge_cancelled() {
    local _json
    _json=$(_forge "$1")
    [[ "$(jq -r '.cancelled' <<< "$_json" 2>/dev/null)" == "true" ]]
}

tui_title() {
    local title="${1}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
}

tui_msg() {
    local title="${1}" msg="${2}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    printf '%s\n' "${msg}" >&2
    _forge '{"widget":"msg","title":"'"${title//\"/\\\"}"'","message":"'"${msg//$'\n'/\\n}"'"}' >/dev/null
}

tui_msg_quick() {
    local title="${1}" msg="${2}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    printf '%s\n' "${msg}" >&2
}

tui_yesno() {
    local title="${1}" msg="${2}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    printf '%s\n' "${msg}" >&2
    msg="${msg//$'\n'/\\n}"
    local result
    result=$(_forge_result '{"widget":"yesno","title":"'"${title//\"/\\\"}"'","message":"'"${msg//\"/\\\"}"'"}')
    [[ "$result" == "true" ]] && return 0 || return 1
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    [[ -n "${msg}" ]] && printf '%s\n' "${msg}" >&2
    msg="${msg//$'\n'/\\n}"
    _forge_result '{"widget":"input","title":"'"${title//\"/\\\"}"'","message":"'"${msg//\"/\\\"}"'","default":"'"${default//\"/\\\"}"'"}'
}

tui_password() {
    local title="${1}" msg="${2}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    [[ -n "${msg}" ]] && printf '%s\n' "${msg}" >&2
    msg="${msg//$'\n'/\\n}"
    _forge_result '{"widget":"password","title":"'"${title//\"/\\\"}"'","message":"'"${msg//\"/\\\"}"'"}'
}

tui_password_confirm() {
    local title="${1:-Password}" prompt="${2:-Enter password:}" confirm_prompt="${3:-Confirm password:}"
    local pass confirm
    while true; do
        printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
        pass=$(_forge_result '{"widget":"password","title":"'"${title//\"/\\\"}"'","message":"'"${prompt//\"/\\\"}"'"}')
        [[ -n "${pass}" ]] || return 1
        confirm=$(_forge_result '{"widget":"password","title":"'"${title//\"/\\\"}"'","message":"'"${confirm_prompt//\"/\\\"}"'"}')
        [[ -n "${confirm}" ]] || return 1
        if [[ "${pass}" == "${confirm}" ]]; then
            printf '%s\n' "${pass}"
            return 0
        fi
        tui_msg_quick "Mismatch" "Passwords do not match. Try again."
    done
}

tui_menu() {
    local title="${1}" msg="${2}"
    shift 2
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    [[ -n "${msg}" ]] && printf '%s\n' "${msg}" >&2
    msg="${msg//$'\n'/\\n}"
    local choices_json
    choices_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
    _forge_result '{"widget":"menu","title":"'"${title//\"/\\\"}"'","message":"'"${msg//\"/\\\"}"'","choices":'"${choices_json}"'}'
}

tui_checklist() {
    local title="${1}" msg="${2}"
    shift 2
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    [[ -n "${msg}" ]] && printf '%s\n' "${msg}" >&2
    msg="${msg//$'\n'/\\n}"
    local choices_json result
    choices_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
    result=$(_forge_result '{"widget":"checklist","title":"'"${title//\"/\\\"}"'","message":"'"${msg//\"/\\\"}"'","choices":'"${choices_json}"'}')
    printf '%s\n' "${result}"
}

tui_spin() {
    local title="${1}" cmd="${2}"
    bash -c "${cmd}" 2>&1 | while IFS= read -r line; do log_info "${line}"; done
}

tui_show_file() {
    local title="${1}" file="${2}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_COLOR_TITLE}")" "${title}" >&2
    _forge '{"widget":"summary","title":"'"${title//\"/\\\"}"'","file":"'"${file}"'"}' >/dev/null
}

tui_edit() {
    local title="${1}" file="${2}"
    printf '\e[1;%sm── %s ──\e[0m\n' "$(_theme_ansi_code "${VFF_TITLE_COLOR}")" "${title}" >&2
    _forge '{"widget":"text","title":"'"${title//\"/\\\"}"'","file":"'"${file}"'"}' >/dev/null
}

tui_multiselect() {
    local title="${1}" msg="${2}" placeholder="${3:-}" min="${4:-0}" max="${5:-0}"
    shift 5 2>/dev/null || shift 3
    local choices_json
    choices_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
    local json
    json='{"widget":"multiselect","title":"'"${title//\"/\\\"}"'","message":"'"${msg//\"/\\\"}"'","choices":'"${choices_json}"''
    [[ -n "$placeholder" ]] && json+=',"placeholder":"'"${placeholder//\"/\\\"}"'"'
    [[ "$min" != "0" ]] && json+=',"min":'"${min}"
    [[ "$max" != "0" ]] && json+=',"max":'"${max}"
    json+='}'
    _forge_result "$json"
}