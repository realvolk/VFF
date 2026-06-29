#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – GRUB bootloader installation

configure_grub() {
    _require_tools grub-install grub-mkconfig mkinitcpio findmnt lsblk blkid
    local kernel="${KERNEL_CHOICE:-linux}"
    local fs_type="${FS_TYPE:-ext4}"
    local root_param=''
    local CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"
    local boot_mode="${VFF_BOOT_MODE:-${ARTIX_BOOT_MODE:-uefi}}"
    local disk
    disk="$(state_get DISK)"
    [[ "${fs_type}" == 'zfs' ]] && root_param='root=ZFS=zroot/root'

    # Initramfs
    log_info "Generating initramfs..."
    ${CHROOT_CMD} /mnt mkinitcpio -P || true
    if ! compgen -G "/mnt/boot/initramfs-*.img" >/dev/null 2>&1; then
        die 'No initramfs image was created'
    fi
    log_info "Initramfs generation complete"

    # UKI (UEFI only)
    if [[ "${boot_mode}" != "bios" ]]; then
        if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
            source "${VFF_DIR}/lib/boot/uki.sh"
            generate_uki "${esp_mount}"
        fi
    fi

    # Detect root device
    local root_device
    root_device=$(${CHROOT_CMD} /mnt findmnt -n -o SOURCE /) || true
    root_device="${root_device%%[*]}"
    [[ -n "${root_device}" ]] || die 'failed to detect root device'

    # BIOS path
    if [[ "${boot_mode}" == "bios" ]]; then
        log_info "Installing GRUB for BIOS..."

        # LUKS cmdline
        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            if ! findmnt /mnt/boot --noheadings &>/dev/null; then
                echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
            fi
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

        # LVM preload
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            echo 'GRUB_PRELOAD_MODULES="lvm dm-mod"' >> /mnt/etc/default/grub
        fi

        # XFS check
        if [[ "${fs_type}" == "xfs" ]]; then
            log_info "Verifying XFS features for GRUB compatibility..."
            if ${CHROOT_CMD} /mnt xfs_info "${root_device}" 2>/dev/null | grep -q 'bigtime=1'; then
                die "XFS bigtime is enabled and may be incompatible with GRUB."
            fi
        fi

        ${CHROOT_CMD} /mnt grub-install --target=i386-pc --boot-directory=/boot "${disk}" || die 'grub-install failed'
        ${CHROOT_CMD} /mnt grub-mkconfig -o /boot/grub/grub.cfg || die 'grub-mkconfig failed'
        log_info "GRUB (BIOS) installed successfully."
        return 0
    fi

    # UEFI path
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

    # LUKS
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        if ! findmnt /mnt/boot --noheadings &>/dev/null; then
            echo 'GRUB_ENABLE_CRYPTODISK=y' >> /mnt/etc/default/grub
        fi
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

    # XFS check
    if [[ "${fs_type}" == "xfs" ]]; then
        log_info "Verifying XFS features for GRUB compatibility..."
        if ${CHROOT_CMD} /mnt xfs_info "${root_device}" 2>/dev/null | grep -q 'bigtime=1'; then
            die "XFS bigtime is enabled and may be incompatible with GRUB."
        fi
    fi

    # Build grub-install arguments
    local -a grub_args=()
    grub_args+=( --target=x86_64-efi )
    grub_args+=( --efi-directory="${esp_mount#/mnt}" )
    grub_args+=( --bootloader-id="${VFF_BOOTLOADER_ID:-VFF}" )
    grub_args+=( --removable )

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        echo 'GRUB_PRELOAD_MODULES="lvm dm-mod"' >> /mnt/etc/default/grub
        grub_args+=( --modules )
        grub_args+=( "part_gpt part_msdos fat lvm dm-mod ext2" )
    fi

    log_info "Installing GRUB..."
    ${CHROOT_CMD} /mnt grub-install "${grub_args[@]}" || die 'grub-install failed'

    if [[ -n "${root_param}" ]]; then
        ${CHROOT_CMD} /mnt sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${root_param}\"|" /etc/default/grub
    fi

    log_info "Generating GRUB configuration..."
    ${CHROOT_CMD} /mnt grub-mkconfig -o /boot/grub/grub.cfg || die 'grub-mkconfig failed'

    log_info "GRUB (UEFI) installed successfully."
}