#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – apk package backend (Alpine Linux)

VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    log_info "Bootstrapping Alpine to ${VFF_TARGET}..."
    apk add --root "${VFF_TARGET}" --initdb alpine-base || die "apk bootstrap failed"
    pkg_install "${pkgs[@]}"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    apk add --root "${VFF_TARGET}" "${pkgs[@]}" || die "apk install failed"
}

pkg_chroot() {
    chroot "${VFF_TARGET}" "$@"
}

pkg_query() {
    apk info --root "${VFF_TARGET}" "${1}" &>/dev/null
}

pkg_repo_setup() {
    log_info "Updating apk repositories..."
    apk update || die "apk update failed"
}

pkg_lock_clean() {
    rm -f "${VFF_TARGET}/var/lib/apk/lock"
}

pkg_install_local() {
    local artifact="${1}"
    [[ -f "${artifact}" ]] || die "pkg_install_local: file not found: ${artifact}"
    cp "${artifact}" "${VFF_TARGET}/root/"
    chroot "${VFF_TARGET}" apk add --allow-untrusted "/root/${artifact##*/}" || die "apk local install failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}