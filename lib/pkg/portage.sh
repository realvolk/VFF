#!/usr/bin/env bash
set -Eeuo pipefail
VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    log_info "Bootstrapping Gentoo stage3…"
    local stage3_url="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt"
    local stage3_latest
    stage3_latest=$(curl -s "$stage3_url" | grep -v '^#' | awk '{print $1}')
    curl -L "https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/$stage3_latest" -o /tmp/stage3.tar.xz
    mkdir -p "$VFF_TARGET"
    tar xpf /tmp/stage3.tar.xz -C "$VFF_TARGET"
    pkg_install "${pkgs[@]}"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    chroot "$VFF_TARGET" emerge --ask=n "${pkgs[@]}"
}

pkg_chroot() {
    chroot "$VFF_TARGET" "$@"
}

pkg_query() {
    chroot "$VFF_TARGET" equery list "$1" &>/dev/null
}

pkg_repo_setup() {
    log_info "Syncing Portage tree…"
    chroot "$VFF_TARGET" emerge-webrsync
}

pkg_lock_clean() {
    rm -f "$VFF_TARGET/var/db/pkg/.lck"
}

pkg_install_local() {
    local artifact="$1"
    cp "$artifact" "$VFF_TARGET/root/"
    chroot "$VFF_TARGET" emerge --ask=n "/root/${artifact##*/}"
    rm -f "$VFF_TARGET/root/${artifact##*/}"
}