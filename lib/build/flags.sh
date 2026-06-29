#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Compilation flags and profiles

VFF_PROFILE_DIR="${VFF_PROFILE_DIR:-${VFF_DIR}/profiles}"

# @brief Load a compilation profile
load_profile() {
    local profile_name="${1:-default}"
    local profile_file="${VFF_PROFILE_DIR}/${profile_name}.sh"
    [[ -f "${profile_file}" ]] || die "Profile not found: ${profile_name}"
    source "${profile_file}"
    export VFF_PROFILE="${profile_name}"
}

# @brief Check if a feature flag is enabled
use_enable() {
    local flag="${1}"
    [[ " ${selected_features[*]:-} " =~ " ${flag} " ]] && return 0 || return 1
}

# @brief Apply package-specific overrides to flags
apply_pkg_flags() {
    VFF_CFLAGS="${PKG_CFLAGS:-${VFF_CFLAGS}}"
    VFF_CXXFLAGS="${PKG_CXXFLAGS:-${VFF_CXXFLAGS}}"
    VFF_LDFLAGS="${PKG_LDFLAGS:-${VFF_LDFLAGS}}"
    VFF_MAKEFLAGS="${PKG_MAKEFLAGS:-${VFF_MAKEFLAGS:-$(nproc)}}"
}

# @brief Compute a hash of the current compilation flags for cache invalidation
flags_hash() {
    local feature_string="${selected_features[*]:-}"
    feature_string="${feature_string:-none}"
    printf '%s%s%s%s%s' \
        "${VFF_CFLAGS}" "${VFF_CXXFLAGS}" "${VFF_LDFLAGS}" \
        "${VFF_MAKEFLAGS}" "${feature_string}" \
        | sha256sum | cut -d' ' -f1
}