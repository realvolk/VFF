#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – init-agnostic service management

service_exists() {
    local svc="${1}" init="${INIT:-openrc}"
    case "${init}" in
        openrc)   [[ -f "/etc/init.d/${svc}" ]] || [[ -f "/mnt/gentoo/etc/init.d/${svc}" ]] ;;
        runit)    [[ -d "/etc/runit/sv/${svc}" ]] || [[ -d "/mnt/gentoo/etc/runit/sv/${svc}" ]] ;;
        dinit)    [[ -f "/etc/dinit.d/${svc}" ]] || [[ -f "/mnt/gentoo/etc/dinit.d/${svc}" ]] ;;
        s6)       [[ -d "/etc/s6/sv/${svc}" ]] || [[ -d "/mnt/gentoo/etc/s6/sv/${svc}" ]] ;;
        systemd)  systemctl list-unit-files "${svc}.service" &>/dev/null ;;
        *)        return 1 ;;
    esac
}

enable_service() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        log_warn "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc)
            if [[ -d /mnt/gentoo ]]; then
                chroot /mnt/gentoo /sbin/rc-update add "${svc}" default
            else
                rc-update add "${svc}" default
            fi
            ;;
        runit)
            local target="/mnt/gentoo"
            [[ -d /mnt/gentoo ]] || target=""
            mkdir -p "${target}/etc/runit/runsvdir/default"
            ln -sf "/etc/runit/sv/${svc}" "${target}/etc/runit/runsvdir/default/${svc}"
            ;;
        dinit)
            local target="/mnt/gentoo"
            [[ -d /mnt/gentoo ]] || target=""
            mkdir -p "${target}/etc/dinit.d/boot.d"
            ln -sf "../${svc}" "${target}/etc/dinit.d/boot.d/${svc}"
            ;;
        s6)       s6-rc-bundle-update add default "${svc}" 2>/dev/null || true ;;
        systemd)
            if [[ -d /mnt/gentoo ]]; then
                chroot /mnt/gentoo /usr/bin/systemctl enable "${svc}"
            else
                systemctl enable "${svc}"
            fi
            ;;
    esac
}

enable_service_boot() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        log_warn "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc)
            if [[ -d /mnt/gentoo ]]; then
                chroot /mnt/gentoo /sbin/rc-update add "${svc}" boot
            else
                rc-update add "${svc}" boot
            fi
            ;;
        runit)
            local target="/mnt/gentoo"
            [[ -d /mnt/gentoo ]] || target=""
            mkdir -p "${target}/etc/runit/runsvdir/boot"
            ln -sf "/etc/runit/sv/${svc}" "${target}/etc/runit/runsvdir/boot/${svc}"
            ;;
        dinit)
            local target="/mnt/gentoo"
            [[ -d /mnt/gentoo ]] || target=""
            mkdir -p "${target}/etc/dinit.d/boot.d"
            ln -sf "../${svc}" "${target}/etc/dinit.d/boot.d/${svc}"
            ;;
        s6)       s6-rc-bundle-update add boot "${svc}" 2>/dev/null || true ;;
        systemd)
            if [[ -d /mnt/gentoo ]]; then
                chroot /mnt/gentoo /usr/bin/systemctl enable "${svc}"
            else
                systemctl enable "${svc}"
            fi
            ;;
    esac
}

disable_service() {
    local svc="${1}" init="${INIT:-openrc}"
    case "${init}" in
        openrc)
            if [[ -d /mnt/gentoo ]]; then
                chroot /mnt/gentoo /sbin/rc-update del "${svc}" default 2>/dev/null || true
                chroot /mnt/gentoo /sbin/rc-update del "${svc}" boot 2>/dev/null || true
            else
                rc-update del "${svc}" default 2>/dev/null || true
                rc-update del "${svc}" boot 2>/dev/null || true
            fi
            ;;
        runit)    rm -f "/mnt/gentoo/etc/runit/runsvdir/default/${svc}" "/mnt/gentoo/etc/runit/runsvdir/boot/${svc}" 2>/dev/null || true ;;
        dinit)    rm -f "/mnt/gentoo/etc/dinit.d/boot.d/${svc}" 2>/dev/null || true ;;
        s6)       s6-rc-bundle-update del default "${svc}" 2>/dev/null || true
                  s6-rc-bundle-update del boot "${svc}" 2>/dev/null || true ;;
        systemd)
            if [[ -d /mnt/gentoo ]]; then
                chroot /mnt/gentoo /usr/bin/systemctl disable "${svc}"
            else
                systemctl disable "${svc}"
            fi
            ;;
    esac
}

start_service() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        log_warn "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc)   rc-service "${svc}" start || true ;;
        runit)    sv up "${svc}" || true ;;
        dinit)    dinitctl start "${svc}" || true ;;
        s6)       s6-rc -u change "${svc}" || true ;;
        systemd)  systemctl start "${svc}" || true ;;
    esac
}

stop_service() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        log_warn "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc)   rc-service "${svc}" stop || true ;;
        runit)    sv down "${svc}" || true ;;
        dinit)    dinitctl stop "${svc}" || true ;;
        s6)       s6-rc -d change "${svc}" || true ;;
        systemd)  systemctl stop "${svc}" || true ;;
    esac
}

restart_service() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        log_warn "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc)   rc-service "${svc}" restart || true ;;
        runit)    sv restart "${svc}" || true ;;
        dinit)    dinitctl restart "${svc}" || true ;;
        s6)       s6-rc -u change "${svc}" 2>/dev/null || true
                  s6-rc -d change "${svc}" 2>/dev/null || true
                  s6-rc -u change "${svc}" 2>/dev/null || true ;;
        systemd)  systemctl restart "${svc}" || true ;;
    esac
}