#!/usr/bin/env bash
set -Eeuo pipefail
VFF_TARGET="${VFF_TARGET:-/mnt/gentoo}"

pkg_bootstrap() {
    local stage3_variant="${STAGE3_VARIANT:-openrc}"
    log_info "Bootstrapping Gentoo stage3 (${stage3_variant})..."

    # Map variant to bouncer URL path
    local variant_path
    case "${stage3_variant}" in
        openrc)          variant_path="latest-stage3-amd64-openrc.txt" ;;
        desktop-openrc)  variant_path="latest-stage3-amd64-desktop-openrc.txt" ;;
        systemd)         variant_path="latest-stage3-amd64-systemd.txt" ;;
        desktop-systemd) variant_path="latest-stage3-amd64-desktop-systemd.txt" ;;
        hardened-openrc) variant_path="latest-stage3-amd64-hardened-openrc.txt" ;;
        musl-openrc)     variant_path="latest-stage3-amd64-musl.txt" ;;
        selinux-openrc)  variant_path="latest-stage3-amd64-selinux-openrc.txt" ;;
        *)               variant_path="latest-stage3-amd64-openrc.txt" ;;
    esac

    local stage3_url="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${variant_path}"
    local stage3_latest
    stage3_latest=$(curl -s "$stage3_url" | grep -v '^#' | awk '{print $1}' | head -n1)

    if [[ -z "${stage3_latest}" ]]; then
        # Fallback to direct URL for openrc
        log_warn "Could not determine latest stage3 for ${stage3_variant}, falling back to openrc"
        stage3_url="https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt"
        stage3_latest=$(curl -s "$stage3_url" | grep -v '^#' | awk '{print $1}' | head -n1)
        [[ -z "${stage3_latest}" ]] && die "Failed to determine stage3 URL"
    fi

    log_info "Downloading stage3: ${stage3_latest}"
    curl -L "https://bouncer.gentoo.org/fetch/root/all/releases/amd64/autobuilds/${stage3_latest}" -o /tmp/stage3.tar.xz

    mkdir -p "$VFF_TARGET"
    log_info "Extracting stage3..."
    tar xpf /tmp/stage3.tar.xz --xattrs-include='*.*' --numeric-owner -C "$VFF_TARGET"
    rm -f /tmp/stage3.tar.xz
    log_info "Stage3 extraction complete."
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    log_info "Installing: ${pkgs[*]}"
    chroot "$VFF_TARGET" /usr/bin/emerge --ask=n --noreplace "${pkgs[@]}"
}

pkg_chroot() {
    chroot "$VFF_TARGET" "$@"
}

pkg_query() {
    chroot "$VFF_TARGET" /usr/bin/equery list "$1" &>/dev/null 2>&1
}

pkg_repo_setup() {
    log_info "Syncing Portage tree..."
    if [[ -d "${VFF_TARGET}/usr" ]]; then
        chroot "$VFF_TARGET" /usr/bin/emerge-webrsync 2>/dev/null || {
            log_warn "emerge-webrsync failed, trying emerge --sync"
            chroot "$VFF_TARGET" /usr/bin/emerge --sync
        }
    else
        emerge-webrsync 2>/dev/null || emerge --sync
    fi
}

pkg_lock_clean() {
    rm -f "$VFF_TARGET/var/db/pkg/.lck" 2>/dev/null || true
}

pkg_install_local() {
    local artifact="$1"
    cp "$artifact" "$VFF_TARGET/root/"
    chroot "$VFF_TARGET" /usr/bin/emerge --ask=n "/root/${artifact##*/}"
    rm -f "$VFF_TARGET/root/${artifact##*/}"
}