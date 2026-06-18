#!/usr/bin/env bash
set -Eeuo pipefail

# @brief Generate a Unified Kernel Image (UKI) for the target system
generate_uki() {
    [[ "$(state_get GENERATE_UKI no)" == "yes" ]] || return 0
    local uki_binary="${UKI_BINARY:-ukify}"
    local uki_package="${UKI_PACKAGE:-eukify}"
    local esp_mount="${1:-/mnt/boot/efi}"

    log_info "Configuring UKI generation..."
    if ! pkg_chroot command -v "${uki_binary}" &>/dev/null; then
        log_info "Installing ${uki_package}..."
        pkg_install "${uki_package}" || die "Failed to install ${uki_package}"
    fi

    local kernel_image=$(ls /mnt/boot/vmlinuz-* 2>/dev/null | head -n1)
    [[ -n "${kernel_image}" ]] || die "No kernel image found for UKI"
    local kernel_name=$(basename "${kernel_image}")
    local kver="${kernel_name#vmlinuz-}"
    local initramfs_name="initramfs-${kver}.img"
    local output="${esp_mount#/mnt}/EFI/Linux/${DISTRO_ID:-linux}-${kver}.efi"

    local uki_cmdline=""
    local fs_type="${FS_TYPE:-ext4}"
    if [[ "${fs_type}" == 'zfs' ]]; then
        uki_cmdline="root=ZFS=zroot/root rw modules=zfs rootfstype=zfs"
    else
        local root_uuid=$(blkid -s UUID -o value "$(findmnt -rn -o SOURCE --target /mnt | sed 's/\[.*\]//')")
        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            local crypt_uuid=$(state_get CRYPT_UUID '') mapper="cryptroot"
            [[ "$(state_get USE_LVM no)" == "yes" ]] && mapper="cryptlvm"
            uki_cmdline+="cryptdevice=UUID=${crypt_uuid}:${mapper} "
        fi
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then uki_cmdline+="root=/dev/vg0/root "
        elif [[ "$(state_get USE_LUKS no)" == "yes" ]]; then uki_cmdline+="root=/dev/mapper/${mapper:-cryptroot} "
        else uki_cmdline+="root=UUID=${root_uuid} "; fi
        uki_cmdline+="rw"
    fi

    pkg_chroot mkdir -p "$(dirname "${output}")"
    log_info "Generating UKI with ${uki_binary}..."
    pkg_chroot "${uki_binary}" build \
        --linux="/boot/${kernel_name}" \
        --initrd="/boot/${initramfs_name}" \
        --cmdline="${uki_cmdline}" \
        --output="${output}" || die "${uki_binary} failed"

    state_set UKI_OUTPUT "${output}"

    local esp_disk="/dev/$(lsblk -no PKNAME "$(findmnt -rn -o SOURCE "${esp_mount}")" | head -n1)"
    local esp_part="$(lsblk -no PARTN "$(findmnt -rn -o SOURCE "${esp_mount}")" | head -n1)"
    pkg_chroot efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
        --label "${DISTRO_NAME:-Linux} (UKI)" \
        --loader "\\EFI\\Linux\\${DISTRO_ID:-linux}-${kver}.efi" \
        --unicode "${uki_cmdline}" --verbose \
        || log_warn "Failed to create UKI EFI boot entry"

    log_info "UKI generated successfully."
}