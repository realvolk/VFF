#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Rebuild detection
VFF_BUILD_DIR="${VFF_BUILD_DIR:-${VFF_TARGET:-/mnt}/var/cache/vff/build}"

# @brief Return 0 if a package needs to be rebuilt
needs_rebuild() {
    local pkgname="${1}"
    local db_entry
    db_entry="$(grep "^${pkgname}|" "${VFF_DB_DIR}/local.db" 2>/dev/null | tail -n1)"
    [[ -n "${db_entry}" ]] || return 0  # not in DB → rebuild

    local saved_flags
    saved_flags="$(echo "${db_entry}" | cut -d'|' -f3)"
    local current_flags
    current_flags="$(flags_hash)"
    [[ "${saved_flags}" == "${current_flags}" ]] || return 0  # flags changed → rebuild

    local recipe_file="${VFF_RECIPES_DIR}/${pkgname}.sh"
    if [[ -f "${recipe_file}" ]]; then
        source "${recipe_file}" 2>/dev/null || true
        local dep
        for dep in "${depends[@]}" "${makedepends[@]}"; do
            local installed_ver db_dep_ver
            installed_ver=$(pkg_query "${dep}" 2>/dev/null | cut -d' ' -f2)  # simplistic; override in backend
            db_dep_ver=$(grep "^${dep}|" "${VFF_DB_DIR}/local.db" | tail -n1 | cut -d'|' -f2)
            [[ "${installed_ver}" == "${db_dep_ver}" ]] || return 0
        done
    fi

    return 1  # up-to-date
}