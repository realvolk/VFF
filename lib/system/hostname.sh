#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – System configuration

configure_system() {
    local hostname timezone locale keymap
    hostname="${HOSTNAME:-vff}"
    timezone="${TIMEZONE:-UTC}"
    locale="${LOCALE:-en_US.UTF-8}"
    keymap="${KEYMAP:-us}"
    local target="${VFF_TARGET:-/mnt}"
    local chroot_cmd="${CHROOT_CMD:-arch-chroot}"

    [[ -n "${hostname}" ]] && [[ "${hostname}" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*$ ]] || die 'invalid hostname'
    [[ -n "${timezone}" ]] || die 'invalid timezone'
    [[ -n "${locale}" ]] || die 'invalid locale'
    [[ -n "${keymap}" ]] || die 'invalid keymap'

    log_info "Configuring hostname..."
    printf '%s\n' "${hostname}" > "${target}/etc/hostname"
    cat <<EOF > "${target}/etc/hosts"
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${hostname}.localdomain ${hostname}
EOF

    log_info "Configuring locale..."
    if grep -q "^#${locale}" "${target}/etc/locale.gen"; then
        sed -i "s/^#${locale}/${locale}/" "${target}/etc/locale.gen"
    elif ! grep -q "^${locale}" "${target}/etc/locale.gen"; then
        printf '%s UTF-8\n' "${locale%% *}" >> "${target}/etc/locale.gen"
    fi
    ${chroot_cmd} "${target}" locale-gen || die 'failed to generate locale'
    cat <<EOF > "${target}/etc/locale.conf"
LANG=${locale}
EOF

    log_info "Configuring keyboard layout..."
    cat <<EOF > "${target}/etc/vconsole.conf"
KEYMAP=${keymap}
EOF

    log_info "Configuring timezone..."
    [[ -e "${target}/usr/share/zoneinfo/${timezone}" ]] || die 'invalid timezone path'
    ln -sf "/usr/share/zoneinfo/${timezone}" "${target}/etc/localtime"
    ${chroot_cmd} "${target}" hwclock --systohc || die 'failed to synchronize hardware clock'

    log_info "System configuration complete."
}