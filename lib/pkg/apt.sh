#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – apt package backend (Debian/Ubuntu)

VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    log_info "Bootstrapping base system to ${VFF_TARGET}..."
    debootstrap --arch amd64 stable "${VFF_TARGET}" https://deb.debian.org/debian || die "debootstrap failed"
    pkg_install "${pkgs[@]}"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    chroot "${VFF_TARGET}" apt-get update || true
    chroot "${VFF_TARGET}" apt-get install -y "${pkgs[@]}" || die "apt-get install failed"
}

pkg_chroot() {
    chroot "${VFF_TARGET}" "$@"
}

pkg_query() {
    chroot "${VFF_TARGET}" dpkg -s "${1}" &>/dev/null
}

pkg_repo_setup() {
    log_info "Updating apt repositories..."
    apt-get update || die "apt-get update failed"
}

pkg_lock_clean() {
    rm -f "${VFF_TARGET}/var/lib/dpkg/lock-frontend" "${VFF_TARGET}/var/lib/apt/lists/lock"
}

pkg_install_local() {
    local artifact="${1}"
    [[ -f "${artifact}" ]] || die "pkg_install_local: file not found: ${artifact}"
    cp "${artifact}" "${VFF_TARGET}/root/"
    chroot "${VFF_TARGET}" dpkg -i "/root/${artifact##*/}" || die "dpkg -i failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}