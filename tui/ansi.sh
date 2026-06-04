#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – native ANSI terminal interface
# No external binaries required.

: "${VFF_COLOR_TITLE:=34}"
: "${VFF_COLOR_ACCENT:=33}"
: "${VFF_COLOR_ERROR:=31}"
: "${VFF_COLOR_SUCCESS:=32}"

_ansi()  { printf '\e[%sm' "${1}"; }
_reset() { printf '\e[0m'; }

tui_title() {
    local title="${1}"
    printf '%s── %s ──%s\n' "$(_ansi "1;${VFF_COLOR_TITLE}")" "${title}" "$(_reset)" >&2
}

tui_msg() {
    local title="${1}" msg="${2}"
    tui_title "${title}"
    printf '%b\n' "${msg}"
    read -rp "Press Enter to continue" _
}

tui_msg_quick() {
    local title="${1}" msg="${2}"
    tui_title "${title}"
    printf '%b\n' "${msg}"
}

tui_yesno() {
    local title="${1}" msg="${2}"
    tui_title "${title}"
    printf '%b\n' "${msg}"
    local ans
    while true; do
        read -rp " [y/N] " ans
        case "${ans}" in
            [Yy]*) return 0 ;;
            [Nn]*|"") return 1 ;;
        esac
    done
}

tui_input() {
    local title="${1}" msg="${2}" default="${3:-}"
    tui_title "${title}"
    [[ -n "${msg}" ]] && printf '%b\n' "${msg}"
    local input
    read -rp " [${default}]: " input
    printf '%s\n' "${input:-${default}}"
}

tui_password() {
    local title="${1}" msg="${2}"
    tui_title "${title}"
    [[ -n "${msg}" ]] && printf '%b\n' "${msg}"
    local pass
    read -rsp "> " pass
    echo >&2
    printf '%s\n' "${pass}"
}

tui_password_confirm() {
    local title="${1:-Password}" prompt="${2:-Enter password:}" confirm_prompt="${3:-Confirm password:}"
    local pass confirm
    while true; do
        tui_title "${title}"
        read -rsp "${prompt} " pass; echo >&2
        read -rsp "${confirm_prompt} " confirm; echo >&2
        if [[ "${pass}" == "${confirm}" ]]; then
            printf '%s\n' "${pass}"
            return 0
        fi
        printf '%s\n' "$(_ansi "${VFF_COLOR_ERROR}")Passwords do not match.$(_reset)"
    done
}

tui_menu() {
    local title="${1}" msg="${2}"
    shift 2
    local -a items=("$@")
    tui_title "${title}"
    [[ -n "${msg}" ]] && printf '%s\n' "${msg}" >&2
    local i choice
    for ((i=0; i<${#items[@]}; i++)); do
        printf '(%d) %s\n' $((i+1)) "${items[$i]}" >&2
    done
    printf '\nChoice (1-%d): ' "${#items[@]}" >&2
    read -r choice
    if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
        printf '%s\n' "${items[$((choice-1))]}"
        return 0
    fi
    return 1
}

tui_checklist() {
    local title="${1}" msg="${2}"
    shift 2
    local -a items=("$@")
    tui_title "${title}"
    [[ -n "${msg}" ]] && printf '%s\n' "${msg}" >&2
    local -a selected=()
    local i ans
    for ((i=0; i<${#items[@]}; i++)); do
        printf '%2d) %s\n' $((i+1)) "${items[$i]}" >&2
    done
    printf '\nNumbers (space-separated, 0=done): ' >&2
    read -r -a ans
    for choice in "${ans[@]}"; do
        if [[ "${choice}" == "0" ]]; then
            ((${#selected[@]})) && printf '%s\n' "${selected[@]}"
            return 0
        elif [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            selected+=("${items[$((choice-1))]}")
        fi
    done
}

tui_spin() { local title="${1}" cmd="${2}"; log_info "${title}"; bash -c "${cmd}"; }

tui_show_file() {
    local title="${1}" file="${2}"
    tui_title "${title}"
    cat "${file}"
}

# @brief Generic selection from a profile-defined choice array
tui_select_from_profile() {
    local title="${1}"
    local choices_var="${2}"
    local state_key="${3}"
    local default="${4}"

    local -a raw=()
    eval "raw=(\"\${${choices_var}[@]}\")"

    if [[ ${#raw[@]} -eq 0 ]]; then
        state_set "${state_key}" "${default}"
        return 0
    fi

    # Detect if this is a paired array (value + description) or flat list
    local has_descriptions=0
    if [[ ${#raw[@]} -ge 2 ]]; then
        # If the first element and second element are completely different
        # (not just case differences), it's likely a paired array.
        # Flat arrays have adjacent elements that are both short lowercase strings.
        local first="${raw[0]}"
        local second="${raw[1]}"
        # Descriptions are longer, have spaces, or start with uppercase
        if [[ "${second}" =~ [A-Z] ]] || [[ "${second}" =~ \  ]] || [[ ${#second} -gt 15 ]]; then
            has_descriptions=1
        fi
    fi
    local -a menu_items=()
    local -a values=()
    local i

    if [[ ${has_descriptions} -eq 1 ]]; then
        for ((i=0; i<${#raw[@]}; i+=2)); do
            values+=("${raw[$i]}")
            if [[ -n "${raw[$i+1]:-}" ]]; then
                menu_items+=("${raw[$i]} - ${raw[$i+1]}")
            else
                menu_items+=("${raw[$i]}")
            fi
        done
    else
        for ((i=0; i<${#raw[@]}; i++)); do
            values+=("${raw[$i]}")
            menu_items+=("${raw[$i]}")
        done
    fi

    local chosen
    chosen=$(tui_menu "${title}" "Select ${title,,}:" "${menu_items[@]}") || {
        state_set "${state_key}" "${default}"
        return 0
    }

    chosen="${chosen%% -*}"
    state_set "${state_key}" "${chosen:-${default}}"
}