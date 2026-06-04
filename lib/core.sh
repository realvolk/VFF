#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – core utilities

# Logging
_ensure_log_dirs() {
    mkdir -p "$(dirname "${LOG_FILE:-/tmp/vff-installer.log}")"
    [[ -d /mnt ]] && mkdir -p "$(dirname "${CHROOT_LOG:-/mnt/var/log/vff-installer.log}")" 2>/dev/null || true
}

log_info() {
    _ensure_log_dirs
    printf '\e[1;34m[*] %s\e[0m\n' "$*" | tee -a "${LOG_FILE:-/tmp/vff-installer.log}" >&2
    [[ -d /mnt ]] && printf '[*] %s\n' "$*" >> "${CHROOT_LOG:-/mnt/var/log/vff-installer.log}" 2>/dev/null || true
}

log_warn() {
    _ensure_log_dirs
    printf '\e[1;33m[!] %s\e[0m\n' "$*" | tee -a "${LOG_FILE:-/tmp/vff-installer.log}" >&2
}

log_error() {
    _ensure_log_dirs
    printf '\e[1;31m[✗] %s\e[0m\n' "$*" | tee -a "${LOG_FILE:-/tmp/vff-installer.log}" >&2
}

die() {
    local reason="${1:-unknown error}"
    log_error "${reason^}"
    exit 1
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || die 'must be run as root'
}

# Linux‑only – uses /sys/firmware/efi. BSD ports must override this function.
require_efi() {
    [[ -d /sys/firmware/efi ]] || die 'system is not booted in UEFI mode'
}

# Network detection (DNS to HTTP to ICMP fallback)
require_internet() {
    if command -v dig &>/dev/null; then
        if dig +short +timeout=3 cloudflare.com &>/dev/null; then return 0; fi
    elif command -v nslookup &>/dev/null; then
        if nslookup -timeout=3 cloudflare.com &>/dev/null; then return 0; fi
    elif command -v curl &>/dev/null; then
        if curl -fsSL --max-time 5 https://1.1.1.1 &>/dev/null; then return 0; fi
    elif ping -c 1 -W 3 1.1.1.1 &>/dev/null; then return 0; fi

    if [[ "${ALLOW_OFFLINE:-no}" == "yes" ]]; then
        log_warn 'continuing in offline mode'
        return 0
    fi
    die 'no internet connection'
}

# Disk helpers
get_partition_name() {
    local disk="${1}" partition="${2}"
    if [[ "${disk}" =~ ^/dev/(nvme|mmcblk|loop) ]]; then
        printf '%sp%s\n' "${disk}" "${partition}"
    else
        printf '%s%s\n' "${disk}" "${partition}"
    fi
}

command_exists() { command -v "${1}" &>/dev/null; }

check_disk_space() {
    local required_gb="${1:-5}" target="${2:-/mnt}"
    local avail_gb
    avail_gb=$(df -BG --output=avail "${target}" 2>/dev/null | tail -1 | tr -d ' G')
    if [[ -n "${avail_gb}" && "${avail_gb}" -lt "${required_gb}" ]]; then
        log_error "Low disk space on ${target}: ${avail_gb}GB available, ${required_gb}GB needed"
        if ! tui_yesno "Low Disk Space" "Only ${avail_gb}GB free on ${target}. Continue anyway?"; then
            die "Not enough disk space"
        fi
    fi
}

# @brief Verify required external tools are available, installing any that are missing
_require_tools() {
    local missing=()
    for tool in "$@"; do
        command -v "${tool}" >/dev/null || missing+=("${tool}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing: ${missing[*]}"
        pkg_install "${missing[@]}" || die "Failed to install: ${missing[*]}"
    fi
}

# Retry logic with exponential backoff
retry_command() {
    local desc="${1}"; shift
    local retries=3 delay=5
    for ((i=1; i<=retries; i++)); do
        if "$@"; then return 0; fi
        log_warn "${desc} failed (attempt ${i}/${retries})"
        if [[ ${i} -lt ${retries} ]]; then
            sleep "${delay}"
            delay=$((delay * 2))
        fi
    done
    return 1
}

# Download with resume support
curl_resume() {
    local url="${1}" out="${2}"
    if [[ -f "${out}" ]]; then
        local remote_size local_size
        remote_size=$(curl -sI "${url}" | grep -i content-length | awk '{print $2}' | tr -d '\r')
        local_size=$(stat -c%s "${out}" 2>/dev/null || echo 0)
        if [[ -n "${remote_size}" && "${local_size}" -lt "${remote_size}" ]]; then
            log_info "Resuming download: ${out} (${local_size}/${remote_size} bytes)"
            curl -C - -L -o "${out}" "${url}" || { log_error "Resume failed: ${url}"; return 1; }
            return 0
        fi
    fi
    curl -L -o "${out}" "${url}" || { log_error "Download failed: ${url}"; return 1; }
    return 0
}

# @brief Source all VFF library modules except pkg backends
vff_source_all() {
    local module
    for module in "${VFF_DIR}"/lib/*.sh "${VFF_DIR}"/lib/**/*.sh; do
        [[ -f "${module}" ]] || continue
        [[ "${module}" == */pkg/* ]] && continue
        [[ "${module}" == */lib/core.sh ]] && continue
        source "${module}"
    done
    source "${VFF_DIR}/tui/ansi.sh"
    source "${VFF_DIR}/tui/selections.sh"
}

# @brief Verify the live environment is ready, install base tools from profile
vff_preflight() {
    require_root
    require_efi
    require_internet
    check_disk_space 3 /mnt
    _require_tools ${VFF_REQUIRED_TOOLS:-}
    log_info "Preflight checks passed."
}

# Run a command without the debug trace file descriptor leaking into child processes
xtrace_safe() {
    ( unset BASH_XTRACEFD; "$@" )
}

# Walk up device mapper layers to find the raw LUKS partition UUID
get_luks_raw_uuid() {
    local dev="$1"
    local current="$dev"

    while [[ -n "$current" ]]; do
        if blkid -o value -s TYPE "$current" 2>/dev/null | grep -q 'crypto_LUKS'; then
            blkid -s UUID -o value "$current" 2>/dev/null || echo ""
            return 0
        fi
        local parent
        parent="$(lsblk -no PKNAME "$current" 2>/dev/null || true)"
        if [[ -z "$parent" ]]; then
            break
        fi
        current="/dev/$parent"
        if [[ "$(lsblk -no TYPE "$current" 2>/dev/null)" == "disk" ]]; then
            break
        fi
    done

    # Fallback: scan all devices for LUKS partitions
    local luks_dev
    luks_dev=$(blkid -o device -t TYPE=crypto_LUKS 2>/dev/null | head -n1)
    if [[ -n "$luks_dev" ]]; then
        blkid -s UUID -o value "$luks_dev" 2>/dev/null || echo ""
        return 0
    fi

    echo ""
}