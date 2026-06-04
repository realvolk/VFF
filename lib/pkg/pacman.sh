#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – pacman package backend (Arch / Artix)

VFF_TARGET="${VFF_TARGET:-/mnt}"
CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"          # <-- Artix profiles must set CHROOT_CMD=artix-chroot

# Caller must set these before sourcing:
# PACMAN_KEYRING="artix"           # or "archlinux"
# PACMAN_BOOTSTRAP="basestrap"     # or "pacstrap"
# PACMAN_ARCH_SUPPORT="yes"        # "yes" if this is Artix needing arch repos

: "${PACMAN_KEYRING:=artix}"
: "${PACMAN_BOOTSTRAP:=basestrap}"
: "${PACMAN_ARCH_SUPPORT:=no}"

pkg_bootstrap() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || die "pkg_bootstrap: no packages specified"
    log_info "Bootstrapping base system to ${VFF_TARGET}..."
    "${PACMAN_BOOTSTRAP}" "${VFF_TARGET}" "${pkgs[@]}" || die "${PACMAN_BOOTSTRAP} failed"
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing to ${VFF_TARGET}: ${pkgs[*]}"
    pacman -S --noconfirm --needed "${pkgs[@]}" 2>/dev/null || true
    "${CHROOT_CMD}" "${VFF_TARGET}" pacman -S --noconfirm --needed "${pkgs[@]}" || die "pacman install failed in target"
}

pkg_chroot() {
    "${CHROOT_CMD}" "${VFF_TARGET}" "$@"
}

pkg_query() {
    pacman --root "${VFF_TARGET}" -Qq "${1}" &>/dev/null
}

pkg_repo_setup() {
    log_info "Initialising ${PACMAN_KEYRING} keyring..."
    pacman-key --init
    pacman-key --populate "${PACMAN_KEYRING}"

    log_info "Synchronising package databases..."
    pacman -Sy --noconfirm || die "Failed to sync package databases"

    if [[ "${PACMAN_ARCH_SUPPORT}" == "yes" ]]; then
        log_info "Enabling Arch Linux repositories..."
        pacman -S --noconfirm --needed artix-archlinux-support
        if ! grep -q '^\[extra\]' /etc/pacman.conf; then
            cat <<'EOF' >> /etc/pacman.conf
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF
        fi
        pacman -Sy --noconfirm
        pacman -S --noconfirm --needed archlinux-keyring
    fi
}

pkg_lock_clean() {
    rm -f "${VFF_TARGET}/var/lib/pacman/db.lck"
}

# Install a local package file into the target
pkg_install_local() {
    local artifact="${1}"
    [[ -f "${artifact}" ]] || die "pkg_install_local: file not found: ${artifact}"
    cp "${artifact}" "${VFF_TARGET}/root/"
    "${CHROOT_CMD}" "${VFF_TARGET}" pacman -U --noconfirm "/root/${artifact##*/}" \
        || die "pacman -U failed"
    rm -f "${VFF_TARGET}/root/${artifact##*/}"
}