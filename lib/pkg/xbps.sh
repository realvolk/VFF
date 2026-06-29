#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Void Linux (XBPS) package backend

pkg_bootstrap() {
    XBPS_ARCH=x86_64 xbps-install -Sy -r "${VFF_TARGET}" base-system
}

pkg_install() {
    xbps-install -Sy -r "${VFF_TARGET}" "$@"
}

pkg_install_local() {
    local artifact="${1}"
    xbps-rindex -a "${artifact}" 2>/dev/null || true
    cp "${artifact}" "${VFF_TARGET}/root/"
    xbps-install -y -r "${VFF_TARGET}" "/root/${artifact##*/}" || die "xbps local install failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}

pkg_chroot() {
    chroot "${VFF_TARGET}" "$@"
}

pkg_query() {
    xbps-query -r "${VFF_TARGET}" "$1" &>/dev/null
}

pkg_repo_setup() {
    xbps-install -S
}

pkg_lock_clean() {
    rm -f "${VFF_TARGET}/var/lib/xbps/db.lck"
}