#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – rEFInd bootloader installation

configure_refind() {
    _require_tools refind-install lsblk blkid findmnt
    local CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"

    local esp_mount=''
    for mp in /mnt/boot/efi /mnt/efi /mnt/boot; do
        if findmnt -rn -o FSTYPE "${mp}" | grep -qx 'vfat'; then
            esp_mount="${mp}"
            break
        fi
    done
    [[ -n "${esp_mount}" ]] || die 'EFI partition not found'

    log_info "Generating initramfs..."
    ${CHROOT_CMD} /mnt mkinitcpio -P || true
    if ! compgen -G "/mnt/boot/initramfs-*.img" >/dev/null 2>&1; then
        die 'No initramfs image was created'
    fi

    # UKI generation (if enabled) — must run after initramfs exists
    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        source "${VFF_DIR}/lib/boot/uki.sh"
        generate_uki "${esp_mount}"
    fi

    local root_uuid
    root_uuid="$(blkid -s UUID -o value "$(findmnt -rn -o SOURCE --target /mnt | sed 's/\[.*\]//')")"

    local refind_root_param="root=UUID=${root_uuid}"

    # LUKS/LVM additions
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local crypt_uuid mapper_name="cryptroot"
        crypt_uuid="$(state_get CRYPT_UUID '')"
        [[ "$(state_get USE_LVM no)" == "yes" ]] && mapper_name="cryptlvm"
        refind_root_param="cryptdevice=UUID=${crypt_uuid}:${mapper_name} "
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            refind_root_param+="root=/dev/vg0/root"
        else
            refind_root_param+="root=/dev/mapper/${mapper_name}"
        fi
    elif [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        refind_root_param="root=/dev/vg0/root"
    fi

    log_info "Installing rEFInd..."
    ${CHROOT_CMD} /mnt bash -c "echo \"${refind_root_param} rw\" > /boot/refind_linux.conf"
    ${CHROOT_CMD} /mnt refind-install || die 'refind-install failed'

    log_info "rEFInd installed successfully."
}