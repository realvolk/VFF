#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – key/value state persistence
# The state file is stored at ${VFF_STATE_FILE} (default /tmp/vff-installer/state.conf).
# All stage markers and logs live under ${VFF_STATE_ROOT} (default /tmp/vff-installer).

readonly VFF_STATE_ROOT="${VFF_STATE_ROOT:-/tmp/vff-installer}"
readonly VFF_STATE_FILE="${VFF_STATE_FILE:-${VFF_STATE_ROOT}/state.conf}"
readonly VFF_STAGE_DIR="${VFF_STAGE_DIR:-${VFF_STATE_ROOT}/stages}"
readonly VFF_LOG_DIR="${VFF_LOG_DIR:-${VFF_STATE_ROOT}/logs}"

# @brief Ensure state directories exist
ensure_state_dirs() {
    mkdir -p "${VFF_STATE_ROOT}" "${VFF_STAGE_DIR}" "${VFF_LOG_DIR}"
}

# @brief Save all known configuration keys to the state file
state_save() {
    ensure_state_dirs
    {
        printf 'DISK=%q\n'               "${DISK:-}"
        printf 'FS_TYPE=%q\n'            "${FS_TYPE:-}"
        printf 'INIT=%q\n'               "${INIT:-}"
        printf 'USE_LUKS=%q\n'           "${USE_LUKS:-no}"
        printf 'LUKS_PASS=%q\n'          "${LUKS_PASS:-}"
        printf 'USE_LVM=%q\n'            "${USE_LVM:-no}"
        printf 'GENERATE_UKI=%q\n'       "${GENERATE_UKI:-no}"
        printf 'BOOTLOADER=%q\n'         "${BOOTLOADER:-}"
        printf 'DISPLAY_MANAGER=%q\n'    "${DISPLAY_MANAGER:-none}"
        printf 'AUDIO_STACK=%q\n'        "${AUDIO_STACK:-pipewire}"
        printf 'SWAP_ENABLED=%q\n'       "${SWAP_ENABLED:-no}"
        printf 'SWAP_SIZE=%q\n'          "${SWAP_SIZE:-0}"
        printf 'EXTRAS=%q\n'             "${EXTRAS:-}"
        printf 'KERNEL_CHOICE=%q\n'      "${KERNEL_CHOICE:-}"
        printf 'HOSTNAME=%q\n'           "${HOSTNAME:-vff}"
        printf 'TIMEZONE=%q\n'           "${TIMEZONE:-UTC}"
        printf 'LOCALE=%q\n'             "${LOCALE:-en_US.UTF-8}"
        printf 'KEYMAP=%q\n'             "${KEYMAP:-us}"
        printf 'BTRFS_LAYOUT=%q\n'       "${BTRFS_LAYOUT:-standard}"
        printf 'WM_DE=%q\n'              "${WM_DE:-}"
        printf 'USER_NAME=%q\n'          "${USER_NAME:-}"
        printf 'USER_PASS=%q\n'          "${USER_PASS:-}"
        printf 'ROOT_PASS=%q\n'          "${ROOT_PASS:-}"
        printf 'USER_SHELL=%q\n'         "${USER_SHELL:-/bin/bash}"
        printf 'PRIV_ESCALATION=%q\n'    "${PRIV_ESCALATION:-sudo}"
        printf 'NETWORK_STACK=%q\n'      "${NETWORK_STACK:-}"
        printf 'X_STACK=%q\n'            "${X_STACK:-xorg}"
        printf 'EFI_PART=%q\n'           "${EFI_PART:-}"
        printf 'ROOT_PART=%q\n'          "${ROOT_PART:-}"
        printf 'SWAP_PART=%q\n'          "${SWAP_PART:-}"
        printf 'INSTALL_MODE=%q\n'       "${INSTALL_MODE:-auto}"
        printf 'VFF_BOOT_MODE=%q\n'      "${VFF_BOOT_MODE:-}"
        printf 'STAGE3_VARIANT=%q\n'     "${STAGE3_VARIANT:-}"
        printf 'PORTAGE_PROFILE=%q\n'    "${PORTAGE_PROFILE:-}"
        printf 'GLOBAL_USE=%q\n'         "${GLOBAL_USE:-}"
        printf 'GENTOO_CFLAGS=%q\n'      "${GENTOO_CFLAGS:-}"
        printf 'GENTOO_MAKEOPTS=%q\n'    "${GENTOO_MAKEOPTS:-}"
        printf 'GENTOO_RUSTFLAGS=%q\n'   "${GENTOO_RUSTFLAGS:-}"
        printf 'ACCEPTED_LICENSES=%q\n'  "${ACCEPTED_LICENSES:-}"
        printf 'USE_BINHOST=%q\n'        "${USE_BINHOST:-no}"
        printf 'BINHOST_URL=%q\n'        "${BINHOST_URL:-}"
        printf 'ENABLED_OVERLAYS=%q\n'   "${ENABLED_OVERLAYS:-}"
        printf 'VIDEO_CARDS=%q\n'        "${VIDEO_CARDS:-}"
        printf 'GPU_USE_FLAGS=%q\n'      "${GPU_USE_FLAGS:-}"
        printf 'DESKTOP_USE_FLAGS=%q\n'  "${DESKTOP_USE_FLAGS:-}"
        printf 'ACCEPT_KEYWORDS_GLOBAL=%q\n' "${ACCEPT_KEYWORDS_GLOBAL:-}"
        printf 'KERNEL_CONFIG_METHOD=%q\n'   "${KERNEL_CONFIG_METHOD:-}"
        printf 'KERNEL_DEFCONFIG=%q\n'   "${KERNEL_DEFCONFIG:-}"
        printf 'QUICK_PROFILE=%q\n'       "${QUICK_PROFILE:-custom}"
        printf 'MICROCODE_PACKAGE=%q\n'  "${MICROCODE_PACKAGE:-}"
    } > "${VFF_STATE_FILE}"
    chmod 600 "${VFF_STATE_FILE}"
}

# @brief Load state from disk
state_load() {
    [[ -f "${VFF_STATE_FILE}" ]] || return 0
    source "${VFF_STATE_FILE}"
}

# @brief Get a value from state, with optional default
state_get() {
    local key="${1}" default="${2:-}"
    printf '%s\n' "${!key:-${default}}"
}

# @brief Set a key/value pair in the state file
state_set() {
    ensure_state_dirs
    local key="${1}" value="${2}"
    export "${key}=${value}"
    local tmpfile="${VFF_STATE_FILE}.tmp.$$"
    if [[ -f "${VFF_STATE_FILE}" ]]; then
        while IFS= read -r line; do
            if [[ "${line}" =~ ^${key}= ]]; then
                printf '%s=%q\n' "${key}" "${value}" >> "${tmpfile}"
            else
                printf '%s\n' "${line}" >> "${tmpfile}"
            fi
        done < "${VFF_STATE_FILE}"
    else
        : > "${tmpfile}"
    fi
    if ! grep -qE "^${key}=" "${VFF_STATE_FILE}" 2>/dev/null; then
        printf '%s=%q\n' "${key}" "${value}" >> "${tmpfile}"
    fi
    mv "${tmpfile}" "${VFF_STATE_FILE}"
}

# @brief Mark a pipeline stage as completed
stage_mark_done()   { ensure_state_dirs; touch "${VFF_STAGE_DIR}/${1}.done"; }

# @brief Check if a stage is already done
stage_is_done()     { [[ -f "${VFF_STAGE_DIR}/${1}.done" ]]; }

# @brief Reset a single stage
stage_reset()       { rm -f "${VFF_STAGE_DIR}/${1}.done"; }

# @brief Reset all stage markers
stage_reset_all()   { rm -f "${VFF_STAGE_DIR}"/*.done; }

# @brief Return the path to a stage's log file
stage_log_path()    { ensure_state_dirs; printf '%s/%s.log\n' "${VFF_LOG_DIR}" "${1}"; }

# @brief Skip a stage if it is already completed
stage_should_skip() {
    local stage="${1}"
    if ! stage_is_done "${stage}"; then
        return 1
    fi
    printf '[*] %s stage already completed. Skipping...\n' "${stage^}"
    return 0
}