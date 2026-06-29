#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – GRUB bootloader installation

configure_grub() {
    _require_tools grub-install grub-mkconfig findmnt lsblk blkid
    local kernel="${KERNEL_CHOICE:-linux}"
    local fs_type="${FS_TYPE:-ext4}"
    local root_param=''
    local boot_mode="${VFF_BOOT_MODE:-uefi}"
    local init="${INIT:-openrc}"
    local target="${VFF_TARGET:-/mnt/gentoo}"
    local disk
    disk="$(state_get DISK)"
    [[ "${fs_type}" == 'zfs' ]] && root_param='root=ZFS=zroot/root'

    log_info "Generating initramfs..."
    if command -v dracut &>/dev/null; then
        if [[ -d "${target}" ]]; then
            chroot "${target}" /usr/bin/dracut --force --regenerate-all 2>/dev/null || true
        else
            dracut --force --regenerate-all 2>/dev/null || true
        fi
    elif command -v genkernel &>/dev/null; then
        if [[ -d "${target}" ]]; then
            chroot "${target}" /usr/bin/genkernel --install initramfs 2>/dev/null || true
        else
            genkernel --install initramfs 2>/dev/null || true
        fi
    fi

    if ! compgen -G "${target}/boot/initramfs-*.img" >/dev/null 2>&1 && ! compgen -G "${target}/boot/initrd-*" >/dev/null 2>&1; then
        log_warn "No initramfs image was created — this may be fine for simple configurations"
    fi
    log_info "Initramfs generation complete"

    # UKI (UEFI only)
    if [[ "${boot_mode}" != "bios" ]]; then
        if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
            source "${VFF_DIR}/lib/boot/uki.sh"
            generate_uki "${esp_mount:-/mnt/gentoo/efi}"
        fi
    fi

    # Detect root device
    local root_device
    root_device=$(findmnt -n -o SOURCE / 2>/dev/null || findmnt -n -o SOURCE /mnt/gentoo 2>/dev/null || true)
    root_device="${root_device%%[*]}"
    [[ -n "${root_device}" ]] || die 'failed to detect root device'

    # BIOS path
    if [[ "${boot_mode}" == "bios" ]]; then
        log_info "Installing GRUB for BIOS..."

        # LUKS cmdline
        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            if ! findmnt "${target}/boot" --noheadings &>/dev/null; then
                echo 'GRUB_ENABLE_CRYPTODISK=y' >> "${target}/etc/default/grub"
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
            sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 ${grub_cmdline}\"|" "${target}/etc/default/grub"
        fi

        # LVM preload
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            echo 'GRUB_PRELOAD_MODULES="lvm dm-mod"' >> "${target}/etc/default/grub"
        fi

        # XFS check
        if [[ "${fs_type}" == "xfs" ]]; then
            log_info "Verifying XFS features for GRUB compatibility..."
            if chroot "${target}" /usr/sbin/xfs_info "${root_device}" 2>/dev/null | grep -q 'bigtime=1'; then
                die "XFS bigtime is enabled and may be incompatible with GRUB."
            fi
        fi

        # systemd init parameter
        if [[ "${init}" == "systemd" ]]; then
            sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 init=/lib/systemd/systemd\"|" "${target}/etc/default/grub"
        fi

        chroot "${target}" /usr/sbin/grub-install --target=i386-pc --boot-directory=/boot "${disk}" || die 'grub-install failed'
        chroot "${target}" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg || die 'grub-mkconfig failed'
        log_info "GRUB (BIOS) installed successfully."
        return 0
    fi

    # UEFI path
    local esp_mount=''
    for mp in /mnt/gentoo/efi /mnt/gentoo/boot/efi /mnt/gentoo/boot; do
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

    # Set GRUB_PLATFORMS for UEFI
    echo 'GRUB_PLATFORMS="efi-64"' >> "${target}/etc/portage/make.conf"

    # LUKS
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        if ! findmnt "${target}/boot" --noheadings &>/dev/null; then
            echo 'GRUB_ENABLE_CRYPTODISK=y' >> "${target}/etc/default/grub"
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
        sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 ${grub_cmdline}\"|" "${target}/etc/default/grub"
    fi

    # XFS check
    if [[ "${fs_type}" == "xfs" ]]; then
        log_info "Verifying XFS features for GRUB compatibility..."
        if chroot "${target}" /usr/sbin/xfs_info "${root_device}" 2>/dev/null | grep -q 'bigtime=1'; then
            die "XFS bigtime is enabled and may be incompatible with GRUB."
        fi
    fi

    # Build grub-install arguments
    local -a grub_args=()
    grub_args+=( --target=x86_64-efi )
    grub_args+=( --efi-directory="${esp_mount#/mnt/gentoo}" )
    grub_args+=( --bootloader-id="${VFF_BOOTLOADER_ID:-VFF}" )
    grub_args+=( --removable )

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        echo 'GRUB_PRELOAD_MODULES="lvm dm-mod"' >> "${target}/etc/default/grub"
        grub_args+=( --modules )
        grub_args+=( "part_gpt part_msdos fat lvm dm-mod ext2" )
    fi

    # systemd init parameter
    if [[ "${init}" == "systemd" ]]; then
        sed -i "s|^GRUB_CMDLINE_LINUX=\"\(.*\)\"|GRUB_CMDLINE_LINUX=\"\1 init=/lib/systemd/systemd\"|" "${target}/etc/default/grub"
    fi

    log_info "Installing GRUB..."
    chroot "${target}" /usr/sbin/grub-install "${grub_args[@]}" || die 'grub-install failed'

    if [[ -n "${root_param}" ]]; then
        sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${root_param}\"|" "${target}/etc/default/grub"
    fi

    # os-prober for dual-boot
    if [[ "$(state_get ENABLE_OS_PROBER no)" == "yes" ]]; then
        echo 'GRUB_DISABLE_OS_PROBER=false' >> "${target}/etc/default/grub"
        # Bind-mount udev for os-prober in chroot
        mkdir -p "${target}/run/udev"
        mount -o bind /run/udev "${target}/run/udev" 2>/dev/null || true
        mount --make-rslave "${target}/run/udev" 2>/dev/null || true
    fi

    log_info "Generating GRUB configuration..."
    chroot "${target}" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg || die 'grub-mkconfig failed'

    # Cleanup os-prober bind mount
    if [[ "$(state_get ENABLE_OS_PROBER no)" == "yes" ]]; then
        umount "${target}/run/udev" 2>/dev/null || true
    fi

    log_info "GRUB (UEFI) installed successfully."
}