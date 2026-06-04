#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Recipe and system validation

# @brief Validate a recipe file
validate_recipe() {
    local recipe_name="${1}"
    local recipe_file="${VFF_RECIPES_DIR}/${recipe_name}.sh"
    [[ -f "${recipe_file}" ]] || die "Recipe file missing: ${recipe_file}"

    local pkgname='' pkgver='' pkgrel='' sources=() depends=() makedepends=()
    unset -f prepare configure build check package 2>/dev/null || true
    source "${recipe_file}"

    [[ -n "${pkgname}" ]] || die "Recipe ${recipe_name}: pkgname missing"
    [[ -n "${pkgver}" ]]  || die "Recipe ${recipe_name}: pkgver missing"
    [[ -n "${pkgrel}" ]]  || die "Recipe ${recipe_name}: pkgrel missing"
    [[ "${#sources[@]}" -gt 0 ]] || die "Recipe ${recipe_name}: sources empty"

    if ! declare -f build >/dev/null; then die "Recipe ${recipe_name}: build() function missing"; fi
    if ! declare -f package >/dev/null; then die "Recipe ${recipe_name}: package() function missing"; fi

    local src entry
    for src in "${sources[@]}"; do
        IFS='|' read -ra entry <<< "${src}"
        [[ "${#entry[@]}" -eq 3 ]] || die "Recipe ${recipe_name}: malformed source entry: ${src}"
    done
}

# @brief Post-build system validation (distribution-specific parts should be overridden)
validate_system() {
    log_info "Running post-build system validation..."
    # Generic check: ensure the built kernel image exists if a custom kernel was built
    if [[ -n "$(state_get POWERUSER_PACKAGES)" ]] && [[ " $(state_get POWERUSER_PACKAGES) " =~ " linux " ]]; then
        if [[ ! -f "${VFF_TARGET}/boot/vmlinuz-linux-custom" ]]; then
            log_warn "Custom kernel image not found in ${VFF_TARGET}/boot"
        fi
        if [[ ! -f "${VFF_TARGET}/boot/initramfs-linux-custom.img" ]]; then
            log_warn "No initramfs for custom kernel"
        fi
    fi
}