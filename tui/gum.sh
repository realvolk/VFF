#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – gum TUI backend
# Drop-in replacement for tui/ansi.sh – same function signatures, prettier output.
# Requires: gum (https://github.com/charmbracelet/gum)

: "${VFF_COLOR_TITLE:=212}"
: "${VFF_COLOR_ACCENT:=34}"
: "${VFF_COLOR_ERROR:=196}"
: "${VFF_COLOR_SUCCESS:=34}"

tui_title() {
    local title="${1}"
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──" >&2
}

tui_msg() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──"
    gum format "${msg}"
    gum confirm "Press Enter to continue" --affirmative="OK" --timeout=0 </dev/tty 2>/dev/null || true
}

tui_msg_quick() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──"
    gum format "${msg}"
}

tui_yesno() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──"
    gum format "${msg}"
    gum confirm </dev/tty
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}" result
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    result=$(gum input --value "${default}" --prompt "> " </dev/tty) || true
    printf '%s' "${result}"
}

tui_password() {
    local title="${1}" msg="${2}"
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum input --password --prompt "> " </dev/tty || true
}

tui_password_confirm() {
    local title="${1:-Password}" prompt="${2:-Enter password:}" confirm_prompt="${3:-Confirm password:}"
    local pass confirm
    while true; do
        gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──" >&2
        pass=$(gum input --password --prompt "${prompt}: " </dev/tty) || true
        [[ -n "${pass}" ]] || return 1
        confirm=$(gum input --password --prompt "${confirm_prompt}: " </dev/tty) || true
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
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --height=15 "$@" </dev/tty
}

tui_checklist() {
    local title="${1}" msg="${2}"
    shift 2
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──" >&2
    [[ -n "${msg}" ]] && gum format "${msg}" >&2
    gum choose --no-limit --height=15 "$@" </dev/tty
}

tui_spin() {
    local title="${1}" cmd="${2}"
    gum spin --spinner dot --title "${title}" -- bash -c "${cmd}" 2>&1 | while IFS= read -r line; do log_info "${line}"; done
}

tui_show_file() {
    local title="${1}" file="${2}"
    gum style --bold --foreground "${VFF_COLOR_TITLE}" "── ${title} ──"
    gum pager < "${file}"
}