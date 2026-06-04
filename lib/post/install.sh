#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Post‑install helpers
# Requires: pkg_install, state_get, log_info, and the distro profile
# that defines DESKTOP_PACKAGES, AUDIO_PACKAGES, GPU_PACKAGES, EXTRA_PACKAGES.

# @brief Install the selected desktop environment
install_desktop() {
    local wm_de="${WM_DE:-none}"
    local pkgs="${DESKTOP_PACKAGES["${wm_de}"]-}"
    if [[ -n "${pkgs}" ]]; then
        pkg_install ${pkgs}
    fi
}

# @brief Install the selected audio stack
install_audio() {
    local stack="${AUDIO_STACK:-pipewire}"
    local pkgs="${AUDIO_PACKAGES["${stack}"]-}"
    if [[ -n "${pkgs}" ]]; then
        pkg_install ${pkgs}
    fi
}

# @brief Install GPU drivers based on detected vendor
install_gpu_drivers() {
    source "${VFF_DIR}/lib/hw/gpu.sh"
    local vendor
    vendor=$(get_gpu_vendor)
    local pkgs="${GPU_PACKAGES["${vendor}"]:-${GPU_PACKAGES["unknown"]}}"
    if [[ -n "${pkgs}" ]]; then
        pkg_install ${pkgs}
    fi
}

# @brief Install extra packages selected by the user
install_extras() {
    local selected="${EXTRAS:-}"
    for pkg in ${selected}; do
        local pkgs="${EXTRA_PACKAGES["${pkg}"]-}"
        if [[ -n "${pkgs}" ]]; then
            pkg_install ${pkgs}
        fi
    done
}

# @brief Run all post‑install steps
run_post_install() {
    install_desktop
    install_audio
    install_gpu_drivers
    install_extras
}