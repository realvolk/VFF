#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Limine bootloader installation
configure_limine() {
    _require_tools limine-deploy lsblk blkid findmnt efibootmgr
    local fs_type="${FS_TYPE:-ext4}"
    local CHROOT_CMD="${CHROOT_CMD:-arch-chroot}"

    local esp_mount=''
    for mp in /mnt/boot/efi /mnt/efi /mnt/boot; do
        if findmnt -rn -o FSTYPE "${mp}" | grep -qx 'vfat'; then esp_mount="${mp}"; break; fi
    done
    [[ -n "${esp_mount}" ]] || die 'EFI partition not found'

    local esp_source esp_disk esp_part
    esp_source="$(findmnt -rn -o SOURCE "${esp_mount}")"
    esp_disk="/dev/$(lsblk -no PKNAME "${esp_source}" | head -n1)"
    esp_part="$(lsblk -no PARTN "${esp_source}" | head -n1)"
    [[ -n "${esp_part}" ]] || die 'failed to detect EFI partition number'

    log_info "Generating initramfs..."
    ${CHROOT_CMD} /mnt mkinitcpio -P || true
    if ! compgen -G "/mnt/boot/initramfs-*.img" >/dev/null 2>&1; then die 'No initramfs image was created'; fi

    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        source "${VFF_DIR}/lib/boot/uki.sh"; generate_uki "${esp_mount}"
    fi

    log_info "Installing Limine..."
    pkg_install limine || die "Failed to install limine"
    mkdir -p /mnt/boot/efi/EFI/BOOT
    if ! cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/efi/EFI/BOOT/ 2>/dev/null; then
        die "Failed to copy BOOTX64.EFI"
    fi

    # Copy kernel and initramfs to ESP for Limine
    cp /mnt/boot/vmlinuz-* "${esp_mount}/" 2>/dev/null || true
    cp /mnt/boot/initramfs-*.img "${esp_mount}/" 2>/dev/null || true
    if [[ -f /mnt/boot/amd-ucode.img ]]; then cp /mnt/boot/amd-ucode.img "${esp_mount}/"; fi
    if [[ -f /mnt/boot/intel-ucode.img ]]; then cp /mnt/boot/intel-ucode.img "${esp_mount}/"; fi

    local limine_kernel=$(ls /mnt/boot/vmlinuz-* 2>/dev/null | head -n1)
    local limine_initramfs=$(ls /mnt/boot/initramfs-*.img 2>/dev/null | grep -v fallback | head -n1)
    local limine_microcode=""
    [[ -f /mnt/boot/intel-ucode.img ]] && limine_microcode="intel-ucode.img"
    [[ -f /mnt/boot/amd-ucode.img ]] && limine_microcode="amd-ucode.img"

    local root_uuid=$(blkid -s UUID -o value "$(findmnt -rn -o SOURCE --target /mnt | sed 's/\[.*\]//')")
    local limine_root_cmdline="root=UUID=${root_uuid} rw"
    case "${fs_type}" in
        btrfs) limine_root_cmdline+=" rootfstype=btrfs" ;;
        xfs)   limine_root_cmdline+=" rootfstype=xfs" ;;
        f2fs)  limine_root_cmdline+=" rootfstype=f2fs" ;;
    esac
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local crypt_uuid=$(state_get CRYPT_UUID '') mapper="cryptroot"
        [[ "$(state_get USE_LVM no)" == "yes" ]] && mapper="cryptlvm"
        limine_root_cmdline+=" cryptdevice=UUID=${crypt_uuid}:${mapper}"
    fi
    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then limine_root_cmdline+=" root=/dev/vg0/root"; fi

    log_info "Writing ${esp_mount}/limine.conf..."
    cat > "${esp_mount}/limine.conf" <<LIMINE_EOF
timeout: 5

/Linux
    protocol: linux
    kernel_path: boot():/$(basename "${limine_kernel}")
LIMINE_EOF
    if [[ -n "${limine_microcode}" && -f "/mnt/boot/${limine_microcode}" ]]; then
        cat >> "${esp_mount}/limine.conf" <<LIMINE_EOF
    module_path: boot():/${limine_microcode}
LIMINE_EOF
    fi
    cat >> "${esp_mount}/limine.conf" <<LIMINE_EOF
    module_path: boot():/$(basename "${limine_initramfs}")
    cmdline: ${limine_root_cmdline}
    comment: Boot ${DISTRO_NAME:-Linux}
LIMINE_EOF

    if [[ -f /mnt/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi ]]; then
        cat >> "${esp_mount}/limine.conf" <<'LIMINE_EOF'

/Windows
    protocol: efi
    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
    comment: Boot Windows
LIMINE_EOF
    fi

    log_info "Creating Limine EFI boot entry..."
    pkg_chroot efibootmgr --create --disk "${esp_disk}" --part "${esp_part}" \
        --label 'Limine' --loader '\EFI\BOOT\BOOTX64.EFI' --verbose \
        || log_warn "Failed to create Limine EFI boot entry"

    log_info "Limine installed successfully."
}