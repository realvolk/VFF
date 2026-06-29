#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Network stack setup

setup_networking() {
    local stack="${NETWORK_STACK:-dhcpcd+iwd}" init="${INIT:-openrc}" pkgs=()
    local init_suffix=""

    # Some distros (Artix) suffix init-specific service packages; others (Arch, Gentoo) don't
    case "${VFF_DISTRO:-artix}" in
        artix) init_suffix="-${init}" ;;
        *)     init_suffix="" ;;
    esac

    case "${stack}" in
        networkmanager) pkgs=(networkmanager)
                        [[ -n "${init_suffix}" ]] && pkgs+=("networkmanager${init_suffix}") ;;
        connman)        pkgs=(connman)
                        [[ -n "${init_suffix}" ]] && pkgs+=("connman${init_suffix}") ;;
        dhcpcd+iwd)     pkgs=(dhcpcd iwd)
                        [[ -n "${init_suffix}" ]] && pkgs+=("dhcpcd${init_suffix}" "iwd${init_suffix}") ;;
        none) return 0 ;;
    esac

    pkg_install "${pkgs[@]}"

    case "${stack}" in
        networkmanager) enable_service NetworkManager ;;
        connman)        enable_service connmand ;;
        dhcpcd+iwd)     enable_service dhcpcd; enable_service iwd ;;
    esac
}