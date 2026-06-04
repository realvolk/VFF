#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – EFIStub boot entry

configure_efistub() {
    _require_tools efibootmgr lsblk blkid findmnt
    local fs_type="${FS_TYPE:-ext4}"
    local CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"

    local esp_mount=''
    for mp in /mnt/boot/efi /mnt/efi /mnt/boot; do
        if findmnt -rn -o FSTYPE "${mp}" | grep -qx 'vfat'; then
            esp_mount="${mp}"
            break
        fi
    done
    [[ -n "${esp_mount}" ]] || die 'EFI partition not found'

    local esp_source esp_disk esp_part
    esp_source="$(findmnt -rn -o SOURCE "${esp_mount}")"
    esp_disk="/dev/$(lsblk -no PKNAME "${esp_source}" | head -n1)"
    esp_part="$(lsblk -no PARTN "${esp_source}" | head -n1)"

    log_info "Generating initramfs..."
    ${CHROOT_CMD} /mnt mkinitcpio -P || true

    # UKI generation (if enabled) — must run after initramfs exists
    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        source "${VFF_DIR}/lib/boot/uki.sh"
        generate_uki "${esp_mount}"
    fi

    local kernel_image initramfs_image
    kernel_image=$(ls /mnt/boot/vmlinuz-* 2>/dev/null | head -n1)
    [[ -n "${kernel_image}" ]] || die 'failed to locate kernel image'
    initramfs_image=$(ls /mnt/boot/initramfs-*.img 2>/dev/null | grep -v fallback | head -n1)
    [[ -n "${initramfs_image}" ]] || die 'failed to locate initramfs image'

    local kernel_basename initramfs_basename
    kernel_basename="$(basename "${kernel_image}")"
    initramfs_basename="$(basename "${initramfs_image}")"

    local esp_artix_dir="${esp_mount}/EFI/Linux"
    mkdir -p "${esp_artix_dir}"
    cp -f "${kernel_image}" "${esp_artix_dir}/${kernel_basename}"
    cp -f "${initramfs_image}" "${esp_artix_dir}/${initramfs_basename}"

    local root_uuid
    root_uuid="$(blkid -s UUID -o value "$(findmnt -rn -o SOURCE --target /mnt | sed 's/\[.*\]//')")"

    local cmdline="root=UUID=${root_uuid} rw"

    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local crypt_uuid mapper_name="cryptroot"
        crypt_uuid="$(state_get CRYPT_UUID '')"
        [[ "$(state_get USE_LVM no)" == "yes" ]] && mapper_name="cryptlvm"
        cmdline+=" cryptdevice=UUID=${crypt_uuid}:${mapper_name}"
    fi
    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        cmdline+=" root=/dev/vg0/root"
    fi

    cmdline+=" initrd=\\EFI\\Linux\\${initramfs_basename}"

    log_info "Creating EFI boot entry..."
    pkg_chroot efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
        --label "${DISTRO_NAME:-Linux}" --loader "\\EFI\\Linux\\${kernel_basename}" \
        --unicode "${cmdline}" --verbose \
        || die 'failed to create EFI boot entry'

    log_info "EFIStub configured successfully."
}