#!/usr/bin/env bash
set -Eeuo pipefail
VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    log_info "Bootstrapping NixOS …"
    curl -L https://nixos.org/nix/install | sh
    . /root/.nix-profile/etc/profile.d/nix.sh
    nix-channel --add https://nixos.org/channels/nixos-unstable nixos
    nix-channel --update
    nixos-generate-config --root "$VFF_TARGET"
    pkg_install "$@"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    nix-env -iA nixos."${pkgs[@]}"
}

pkg_chroot() {
    nixos-enter --root "$VFF_TARGET" -- "$@"
}

pkg_query() {
    nix-env -q | grep -qx "$1"
}

pkg_repo_setup() {
    nix-channel --update
}

pkg_lock_clean() {
    rm -f /nix/var/nix/db/db.lock
}

pkg_install_local() {
    local artifact="$1"
    nix-env -i "$artifact"
}