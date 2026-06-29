#!/usr/bin/env bash
set -Eeuo pipefail

# @brief Generate a Unified Kernel Image (UKI) for the target system
generate_uki() {
    [[ "$(state_get GENERATE_UKI no)" == "yes" ]] || return 0
    local esp_mount="${1:-/mnt/gentoo/efi}"
    local target="${VFF_TARGET:-/mnt/gentoo}"
    local init="${INIT:-openrc}"

    log_info "Configuring UKI generation..."

    # Try dracut first, then ukify
    local kernel_image=""
    kernel_image=$(ls "${target}/boot/vmlinuz-"* 2>/dev/null | head -n1)
    [[ -n "${kernel_image}" ]] || die "No kernel image found for UKI"
    local kernel_name=$(basename "${kernel_image}")
    local kver="${kernel_name#vmlinuz-}"

    local output_dir="${esp_mount#/mnt/gentoo}/EFI/Linux"
    mkdir -p "${target}${output_dir}"
    local output="${output_dir}/${DISTRO_ID:-linux}-${kver}.efi"

    local uki_cmdline=""
    local fs_type="${FS_TYPE:-ext4}"
    if [[ "${fs_type}" == 'zfs' ]]; then
        uki_cmdline="root=ZFS=zroot/root rw"
    else
        local root_uuid
        root_uuid=$(blkid -s UUID -o value "$(findmnt -rn -o SOURCE --target /mnt/gentoo | sed 's/\[.*\]//')")
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

    # Use dracut for UKI if available
    if command -v dracut &>/dev/null; then
        log_info "Generating UKI with dracut..."
        chroot "${target}" /usr/bin/dracut --force --uefi --kernel-cmdline "${uki_cmdline}" \
            "${output}" --kver "${kver}" 2>/dev/null || {
            log_warn "dracut UKI generation failed, trying ukify..."
        }
    fi

    # Fallback: use ukify from systemd-utils
    if command -v ukify &>/dev/null || [[ -x "${target}/usr/bin/ukify" ]]; then
        log_info "Generating UKI with ukify..."
        local initramfs_name=""
        initramfs_name=$(ls "${target}/boot/initramfs-${kver}.img" 2>/dev/null | head -n1)
        [[ -z "${initramfs_name}" ]] && initramfs_name=$(ls "${target}/boot/initrd-${kver}" 2>/dev/null | head -n1)

        if [[ -x "${target}/usr/bin/ukify" ]]; then
            chroot "${target}" /usr/bin/ukify build \
                --linux="/boot/${kernel_name}" \
                --initrd="/boot/${initramfs_name##*/}" \
                --cmdline="${uki_cmdline}" \
                --output="${output}" || die "ukify failed"
        else
            ukify build \
                --linux="${target}/boot/${kernel_name}" \
                --initrd="${initramfs_name}" \
                --cmdline="${uki_cmdline}" \
                --output="${target}${output}" || die "ukify failed"
        fi
    fi

    state_set UKI_OUTPUT "${output}"

    # Create EFI boot entry
    if [[ "${boot_mode:-uefi}" != "bios" ]]; then
        local esp_disk="/dev/$(lsblk -no PKNAME "$(findmnt -rn -o SOURCE "${esp_mount}")" | head -n1)"
        local esp_part="$(lsblk -no PARTN "$(findmnt -rn -o SOURCE "${esp_mount}")" | head -n1)"
        chroot "${target}" /usr/sbin/efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
            --label "${DISTRO_NAME:-Linux} (UKI)" \
            --loader "\\EFI\\Linux\\${DISTRO_ID:-linux}-${kver}.efi" \
            --unicode "${uki_cmdline}" --verbose \
            || log_warn "Failed to create UKI EFI boot entry"
    fi

    log_info "UKI generated successfully."
}