#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Unified Kernel Image generation
# Call generate_uki from any bootloader module.
# Profiles must set UKI_BINARY (default: ukify) and UKI_PACKAGE (default: eukify).
# If the binary is not installed, the function attempts to install it via pkg_install.

generate_uki() {
    # Only run if the user requested UKI
    [[ "$(state_get GENERATE_UKI no)" == "yes" ]] || return 0

    local uki_binary="${UKI_BINARY:-ukify}"
    local uki_package="${UKI_PACKAGE:-eukify}"
    local esp_mount="${1:-/mnt/boot/efi}"

    log_info "Configuring UKI generation..."

    # Ensure the UKI generator is installed in the target
    if ! pkg_chroot command -v "${uki_binary}" &>/dev/null; then
        log_info "Installing ${uki_package}..."
        pkg_install "${uki_package}" || die "Failed to install ${uki_package}"
    fi

    # Detect kernel and initramfs
    local kernel_image kernel_name kver initramfs_name output
    kernel_image=$(ls /mnt/boot/vmlinuz-* 2>/dev/null | head -n1)
    [[ -n "${kernel_image}" ]] || die "No kernel image found for UKI"
    kernel_name=$(basename "${kernel_image}")
    kver="${kernel_name#vmlinuz-}"
    initramfs_name="initramfs-${kver}.img"
    output="${esp_mount#/mnt}/EFI/Linux/${DISTRO_ID:-linux}-${kver}.efi"

    # Build cmdline
    local uki_cmdline=""
    local fs_type="${FS_TYPE:-ext4}"
    if [[ "${fs_type}" == 'zfs' ]]; then
        uki_cmdline="root=ZFS=zroot/root rw modules=zfs rootfstype=zfs"
    else
        local root_uuid
        root_uuid=$(blkid -s UUID -o value "$(findmnt -rn -o SOURCE --target /mnt | sed 's/\[.*\]//')")
        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            local crypt_uuid mapper_name="cryptroot"
            crypt_uuid=$(state_get CRYPT_UUID '')
            [[ "$(state_get USE_LVM no)" == "yes" ]] && mapper_name="cryptlvm"
            uki_cmdline+="cryptdevice=UUID=${crypt_uuid}:${mapper_name} "
        fi
        if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
            uki_cmdline+="root=/dev/vg0/root "
        elif [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            uki_cmdline+="root=/dev/mapper/${mapper_name:-cryptroot} "
        else
            uki_cmdline+="root=UUID=${root_uuid} "
        fi
        uki_cmdline+="rw"
    fi

    # Ensure output directory exists
    pkg_chroot mkdir -p "$(dirname "${output}")"

    log_info "Generating UKI with ${uki_binary}..."
    pkg_chroot "${uki_binary}" build \
        --linux="/boot/${kernel_name}" \
        --initrd="/boot/${initramfs_name}" \
        --cmdline="${uki_cmdline}" \
        --output="${output}" || die "${uki_binary} failed"

    # Store the output path for the EFI entry creation
    state_set UKI_OUTPUT "${output}"

    # Create EFI boot entry (distro-agnostic)
    local esp_disk esp_part
    esp_disk="/dev/$(lsblk -no PKNAME "$(findmnt -rn -o SOURCE "${esp_mount}")" | head -n1)"
    esp_part="$(lsblk -no PARTN "$(findmnt -rn -o SOURCE "${esp_mount}")" | head -n1)"
    pkg_chroot efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
        --label "${DISTRO_NAME:-Linux} (UKI)" \
        --loader "\\EFI\\Linux\\${DISTRO_ID:-linux}-${kver}.efi" \
        --unicode "${uki_cmdline}" --verbose \
        || log_warn "Failed to create UKI EFI boot entry"

    log_info "UKI generated successfully."
}