#!/usr/bin/env bash
set -Eeuo pipefail

configure_users() {
    local username password root_password shell priv_esc
    username="$(state_get USER_NAME)"
    password="$(state_get USER_PASS)"
    root_password="$(state_get ROOT_PASS)"
    shell="$(state_get USER_SHELL /bin/bash)"
    priv_esc="$(state_get PRIV_ESCALATION sudo)"
    local CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"

    [[ "${username}" =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'invalid username'
    case "${shell}" in bash|zsh|fish) ;; *) shell="/bin/bash" ;; esac
    [[ -x "/mnt${shell}" ]] || shell="/bin/bash"

    local root_hash user_hash
    root_hash=$(openssl passwd -6 -- "${root_password}") || die 'hash root password'
    user_hash=$(openssl passwd -6 -- "${password}")     || die 'hash user password'

    log_info "Configuring users..."
    ${CHROOT_CMD} /mnt /bin/bash -c "
        usermod -p '${root_hash}' root
        if ! id '${username}' &>/dev/null; then
            useradd -m -G wheel,audio,video,storage -s '${shell}' '${username}'
            usermod -p '${user_hash}' '${username}'
        fi
        if [[ '${priv_esc}' == 'sudo' ]]; then
            sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
            sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
        fi
    "

    if [[ "${priv_esc}" == "doas" ]]; then
        cat <<'EOF' > /mnt/etc/doas.conf
permit persist :wheel
EOF
        chmod 0400 /mnt/etc/doas.conf
    fi
    log_info "User configuration complete."
}