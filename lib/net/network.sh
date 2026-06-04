#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Network stack setup

setup_networking() {
    local stack="${NETWORK_STACK:-dhcpcd+iwd}" init="${INIT:-openrc}" pkgs=()
    case "${stack}" in
        networkmanager) pkgs=(networkmanager "networkmanager-${init}") ;;
        connman)        pkgs=(connman "connman-${init}") ;;
        dhcpcd+iwd)     pkgs=(dhcpcd iwd "dhcpcd-${init}" "iwd-${init}") ;;
        none) return 0 ;;
    esac

    pkg_install "${pkgs[@]}"

    case "${stack}" in
        networkmanager) enable_service NetworkManager ;;
        connman)        enable_service connmand ;;
        dhcpcd+iwd)     enable_service dhcpcd; enable_service iwd ;;
    esac
}