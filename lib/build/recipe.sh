#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Recipe loader

VFF_RECIPES_DIR="${VFF_RECIPES_DIR:-${VFF_DIR}/recipes}"

# @brief Load a recipe file and export its variables
load_recipe() {
    local recipe_name="${1}"
    local recipe_file="${VFF_RECIPES_DIR}/${recipe_name}.sh"
    [[ -f "${recipe_file}" ]] || die "Recipe not found: ${recipe_name}"

    pkgname='' pkgver='' pkgrel='' desc='' url=''
    sources=() depends=() makedepends=() feature_flags=() provides=()
    unset -f prepare configure build check package 2>/dev/null || true

    source "${recipe_file}"

    [[ -n "${pkgname}" ]] || die "Recipe ${recipe_name} missing pkgname"
    [[ -n "${pkgver}" ]]  || die "Recipe ${recipe_name} missing pkgver"
    [[ -n "${pkgrel}" ]]  || die "Recipe ${recipe_name} missing pkgrel"

    # Guard against recipes that leave arrays unset
    depends=("${depends[@]:-}")
    makedepends=("${makedepends[@]:-}")
    feature_flags=("${feature_flags[@]:-}")
    provides=("${provides[@]:-}")

    export pkgname pkgver pkgrel desc url sources depends makedepends feature_flags provides
}

# @brief List all available recipes
list_recipes() {
    local recipe
    for recipe in "${VFF_RECIPES_DIR}"/*.sh; do
        [[ -f "${recipe}" ]] || continue
        local name
        name="$(basename "${recipe}" .sh)"
        [[ "${name}" == "template" ]] && continue
        local d
        d="$(grep -m1 '^desc=' "${recipe}" | cut -d'"' -f2)"
        printf '%s — %s\n' "${name}" "${d:-no description}"
    done
}