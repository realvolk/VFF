#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – dnf package backend (Fedora/RHEL)

VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    local release="${FEDORA_RELEASE:-41}"
    log_info "Bootstrapping Fedora ${release} to ${VFF_TARGET}..."
    dnf --installroot="${VFF_TARGET}" --releasever="${release}" install -y dnf fedora-release
    pkg_install "${pkgs[@]}"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    dnf --installroot="${VFF_TARGET}" install -y "${pkgs[@]}" || die "dnf install failed"
}

pkg_chroot() {
    chroot "${VFF_TARGET}" "$@"
}

pkg_query() {
    dnf --installroot="${VFF_TARGET}" list installed "${1}" &>/dev/null
}

pkg_repo_setup() {
    log_info "DNF repositories are configured via the bootstrap step."
}

pkg_lock_clean() {
    rm -f "${VFF_TARGET}/var/lib/rpm/.rpm.lock"
}

pkg_install_local() {
    local artifact="${1}"
    cp "${artifact}" "${VFF_TARGET}/root/"
    dnf --installroot="${VFF_TARGET}" install -y "/root/${artifact##*/}" || die "dnf local install failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}