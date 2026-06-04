#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – GRUB bootloader installation

configure_grub() {
    _require_tools grub-install grub-mkconfig mkinitcpio findmnt lsblk blkid
    local kernel="${KERNEL_CHOICE:-linux}"
    local fs_type="${FS_TYPE:-ext4}"
    local root_param=''
    local CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"
    [[ "${fs_type}" == 'zfs' ]] && root_param='root=ZFS=zroot/root'

    # Detect ESP path
    local esp_mount=''
    for mp in /mnt/boot/efi /mnt/efi /mnt/boot; do
        if findmnt -rn -o FSTYPE "${mp}" | grep -qx 'vfat'; then
            esp_mount="${mp}"
            break
        fi
    done
    [[ -n "${esp_mount}" ]] || die 'EFI partition not found'
    log_info "EFI partition mount: ${esp_mount}"

    local esp_source esp_disk esp_part
    esp_source="$(findmnt -rn -o SOURCE "${esp_mount}")"
    esp_disk="/dev/$(lsblk -no PKNAME "${esp_source}" | head -n1)"
    esp_part="$(lsblk -no PARTN "${esp_source}" | head -n1)"
    [[ -n "${esp_part}" ]] || die 'failed to detect EFI partition number'

    log_info "Generating initramfs..."
    ${CHROOT_CMD} /mnt mkinitcpio -P || true
    if ! compgen -G "/mnt/boot/initramfs-*.img" >/dev/null 2>&1; then
        die 'No initramfs image was created'
    fi
    log_info "Initramfs generation complete"

    # Detect root device
    local root_device
    root_device=$(${CHROOT_CMD} /mnt findmnt -n -o SOURCE /) || true
    root_device="${root_device%%[*]}"
    [[ -n "${root_device}" ]] || die 'failed to detect root device'

    # LUKS setup for GRUB
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
        local crypt_uuid mapper_name="cryptroot"
        crypt_uuid="$(state_get CRYPT_UUID '')"
        [[ "$(state_get USE_LVM no)" == "yes" ]] && mapper_name="cryptlvm"

        local grub_cmdline="cryptdevice=UUID=${crypt_uuid}:${mapper_name}"
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            grub_cmdline+=" root=/dev/vg0/root"
        else
            grub_cmdline+=" root=/dev/mapper/${mapper_name}"
        fi
        ${CHROOT_CMD} /mnt sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 ${grub_cmdline}\"|" /etc/default/grub
    fi

    # Verify XFS bigtime compatibility
    if [[ "${fs_type}" == "xfs" ]]; then
        log_info "Verifying XFS features for GRUB compatibility..."
        if ${CHROOT_CMD} /mnt xfs_info "${root_device}" 2>/dev/null | grep -q 'bigtime=1'; then
            die "XFS bigtime is enabled and may be incompatible with GRUB."
        fi
    fi

    log_info "Installing GRUB..."
    ${CHROOT_CMD} /mnt grub-install --target=x86_64-efi --efi-directory="${esp_mount#/mnt}" --bootloader-id="${VFF_BOOTLOADER_ID:-VFF}" \
        || die 'grub-install failed'

    if [[ -n "${root_param}" ]]; then
        ${CHROOT_CMD} /mnt sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${root_param}\"|" /etc/default/grub
    fi

    log_info "Generating GRUB configuration..."
    ${CHROOT_CMD} /mnt grub-mkconfig -o /boot/grub/grub.cfg || die 'grub-mkconfig failed'

    log_info "Bootloader setup complete."
}