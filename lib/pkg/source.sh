#!/usr/bin/env bash
set -Eeuo pipefail
VFF_TARGET="${VFF_TARGET:-/mnt}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    log_info "LFS / source-only bootstrap: using VFF build engine…"
    source "${VFF_DIR}/lib/build/engine.sh"
    source "${VFF_DIR}/lib/build/recipe.sh"
    for pkg in "${pkgs[@]}"; do
        load_recipe "$pkg"
        build_package "$pkg"
    done
}

pkg_install() { pkg_bootstrap "$@"; }
pkg_chroot() { chroot "$VFF_TARGET" "$@"; }
pkg_query() { [[ -f "$VFF_TARGET/usr/local/bin/$1" ]] || [[ -f "$VFF_TARGET/usr/bin/$1" ]]; }
pkg_repo_setup() { log_info "Source backend – no repository setup needed."; }
pkg_lock_clean() { :; }

pkg_install_local() {
    local artifact="$1"
    cp "$artifact" "$VFF_TARGET/tmp/"
    chroot "$VFF_TARGET" /bin/sh -c "cd /tmp && tar xf ${artifact##*/} && cd * && make install"
    rm -rf "$VFF_TARGET/tmp/${artifact##*/}"
}