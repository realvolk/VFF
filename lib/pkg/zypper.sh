#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – zypper package backend (openSUSE)

VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    log_info "Bootstrapping openSUSE to ${VFF_TARGET}..."
    zypper --root "${VFF_TARGET}" install -y patterns-base-base || die "zypper bootstrap failed"
    pkg_install "${pkgs[@]}"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    zypper --root "${VFF_TARGET}" install -y "${pkgs[@]}" || die "zypper install failed"
}

pkg_chroot() {
    chroot "${VFF_TARGET}" "$@"
}

pkg_query() {
    zypper --root "${VFF_TARGET}" search -i "${1}" &>/dev/null
}

pkg_repo_setup() {
    log_info "Refreshing zypper repositories..."
    zypper refresh || die "zypper refresh failed"
}

pkg_lock_clean() {
    rm -f "${VFF_TARGET}/var/lib/zypp/lock"
}

pkg_install_local() {
    local artifact="${1}"
    cp "${artifact}" "${VFF_TARGET}/root/"
    zypper --root "${VFF_TARGET}" install -y "/root/${artifact##*/}" || die "zypper local install failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}