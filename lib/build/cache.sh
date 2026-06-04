#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Build artifact cache

VFF_BUILD_DIR="${VFF_BUILD_DIR:-${VFF_TARGET:-/mnt}/var/cache/vff/build}"
CACHE_DIR="${VFF_BUILD_DIR}/artifacts"

# @brief Check if a package with the same flags is already cached
cache_hit() {
    local pkgname="${1}" pkgver="${2}" flags_hash="${3}"
    local artifact="${CACHE_DIR}/${pkgname}-${pkgver}-*-x86_64.pkg.tar.zst"

    if compgen -G "${artifact}" >/dev/null 2>&1; then
        local entry
        entry="$(grep "^${pkgname}|${pkgver}-" "${VFF_DB_DIR}/local.db" 2>/dev/null)"
        local cached_hash
        cached_hash="$(printf '%s' "${entry}" | cut -d'|' -f3)"
        [[ "${cached_hash}" == "${flags_hash}" ]] && return 0
    fi
    return 1
}

# @brief Remove obsolete cached packages
cache_clean() {
    local pkgname
    for pkgname in $(cut -d'|' -f1 "${VFF_DB_DIR}/local.db" | sort -u); do
        local latest
        latest="$(grep "^${pkgname}|" "${VFF_DB_DIR}/local.db" | sort -t'|' -k2 -V | tail -n1 | cut -d'|' -f2)"
        find "${CACHE_DIR}" -name "${pkgname}-*" ! -name "${pkgname}-${latest}-*" -delete 2>/dev/null || true
    done
    log_info "Cache cleaned."
}