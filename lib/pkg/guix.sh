#!/usr/bin/env bash
set -Eeuo pipefail
VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    log_info "Bootstrapping Guix System…"
    guix pull
    guix system init --no-bootloader "$VFF_TARGET"
    pkg_install "$@"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    guix package -r "$VFF_TARGET" -i "${pkgs[@]}"
}

pkg_chroot() {
    guix system container --root="$VFF_TARGET" -- "$@"
}

pkg_query() {
    guix package -I | grep -qx "$1"
}

pkg_repo_setup() {
    guix pull
}

pkg_lock_clean() {
    rm -f /var/guix/db/db.lock
}

pkg_install_local() {
    local artifact="$1"
    guix package -f "$artifact"
}