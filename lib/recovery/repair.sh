#!/usr/bin/env bash
set -Eeuo pipefail

# @brief Regenerate fstab
repair_fstab() {
    local issues=$(state_get FSTAB_ISSUES none)
    if [[ "${issues}" == "missing" ]] || [[ "${issues}" != "none" ]]; then
        if tui_yesno "Repair fstab" "Regenerate fstab?"; then
            fstabgen -U /mnt > /mnt/etc/fstab && log_info "fstab regenerated."
        fi
    fi
}

# @brief Remove stale lock and reinstall base packages
repair_packages() {
    local issues=$(state_get PKG_ISSUES none)
    if [[ "${issues}" =~ stale-lock ]]; then
        if tui_yesno "Remove lock" "Remove stale package lock?"; then pkg_lock_clean; fi
    fi
    if [[ "${issues}" =~ base-missing ]]; then
        if tui_yesno "Reinstall base" "Reinstall base system?"; then
            pkg_bootstrap "${BASE_PACKAGES[@]}"
        fi
    fi
    if [[ "${issues}" =~ broken-pkgs:([0-9]+) ]]; then
        local count="${BASH_REMATCH[1]}"
        log_warn "${count} packages have missing files."
        if tui_yesno "Repair broken packages" "Reinstall all packages with missing files?"; then
            local broken_list="$(state_get BROKEN_PACKAGES "")"
            if [[ -n "${broken_list}" ]]; then
                log_info "Reinstalling ${count} broken packages..."
                local -a pkgs; read -ra pkgs <<< "${broken_list}"
                local batch=() i=0 success=0 fail=0
                for pkg in "${pkgs[@]}"; do
                    batch+=("${pkg}")
                    ((i++))
                    if [[ ${i} -ge 20 ]]; then
                        local batch_size=${#batch[@]}
                        log_info "  Batch: ${batch[*]}"
                        if pkg_install "${batch[@]}"; then
                            ((success += batch_size))
                        else
                            log_warn "  Batch failed — trying individually..."
                            for b in "${batch[@]}"; do
                                if pkg_install "${b}"; then ((success++)); else log_warn "  Failed: ${b}"; ((fail++)); fi
                            done
                        fi
                        batch=() i=0
                    fi
                done
                if [[ ${#batch[@]} -gt 0 ]]; then
                    local batch_size=${#batch[@]}
                    if pkg_install "${batch[@]}"; then ((success += batch_size))
                    else
                        for b in "${batch[@]}"; do
                            if pkg_install "${b}"; then ((success++)); else log_warn "  Failed: ${b}"; ((fail++)); fi
                        done
                    fi
                fi
                log_info "Reinstall complete: ${success} succeeded, ${fail} failed"
            fi
        fi
    fi
}

# @brief Regenerate UKI if missing
repair_uki() {
    [[ "$(state_get GENERATE_UKI no)" == "yes" ]] || return 0
    if ! compgen -G "/mnt/boot/efi/EFI/Linux/"*.efi >/dev/null 2>&1; then
        if tui_yesno "Repair UKI" "Regenerate UKI?"; then
            source "${VFF_DIR}/lib/boot/uki.sh"
            generate_uki "/mnt/boot/efi"
        fi
    fi
}

# @brief Repair boot issues (kernel, initramfs, bootloader, init symlink)
repair_boot() {
    local issues=$(state_get BOOT_ISSUES none)
    if [[ "${issues}" =~ no-kernel ]]; then
        if tui_yesno "Reinstall kernel" "Reinstall kernel?"; then
            local kpkg=$(_kernel_pkg "$(state_get KERNEL_CHOICE)")
            [[ -n "${kpkg}" ]] && pkg_install ${kpkg}
        fi
    fi
    if [[ "${issues}" =~ no-initramfs ]]; then
        if tui_yesno "Regenerate initramfs" "Run mkinitcpio?"; then
            pkg_chroot mkinitcpio -P
        fi
    fi
    if [[ "${issues}" =~ no-init ]]; then
        log_warn "/sbin/init missing."
        local init=$(detect_init 2>/dev/null || state_get INIT openrc)
        if tui_yesno "Repair init" "Create /sbin/init symlink to ${init}?"; then
            pkg_chroot ln -sf "/usr/bin/${init}" /sbin/init
            log_info "Init symlink created."
        fi
    fi
    if [[ "${issues}" =~ no-efi-entry ]]; then
        if tui_yesno "Reinstall bootloader" "Reinstall $(state_get BOOTLOADER)?"; then
            source "${VFF_DIR}/lib/boot/$(state_get BOOTLOADER).sh"
            configure_grub  # calls appropriate bootloader function
        fi
    fi
    if [[ "${issues}" =~ no-uki ]]; then repair_uki; fi
    if [[ "${issues}" =~ missing-cryptdevice ]]; then
        if tui_yesno "Repair cmdline" "Regenerate bootloader config?"; then
            source "${VFF_DIR}/lib/boot/$(state_get BOOTLOADER).sh"
            configure_grub
        fi
    fi
    if [[ "${issues}" =~ missing-encrypt-hook ]]; then
        if tui_yesno "Repair hooks" "Add encrypt hook?"; then
            pkg_chroot sed -i '/^HOOKS=/s/\(block\)/\1 encrypt/' /etc/mkinitcpio.conf
            pkg_chroot mkinitcpio -P
        fi
    fi
}

# @brief Repair filesystem corruption (safe/destructive)
repair_filesystem() {
    local root_part=$(findmnt -no SOURCE /mnt 2>/dev/null || true)
    local fs_type=$(state_get FS_TYPE ext4)
    if [[ -z "${root_part}" || ! -b "${root_part}" ]]; then
        log_error "Could not determine root partition — is /mnt mounted?"; return 1
    fi

    tui_msg "Filesystem Repair" "Filesystem: ${fs_type} on ${root_part}\n\nSafe – non-destructive check\nDestructive – aggressive repair, may discard data"
    local method=$(tui_menu "Repair Method" "Select repair approach:" "Safe (fsck -p / equivalent)" "Destructive (fsck -f -y / equivalent)" "Cancel") || return 1
    [[ "${method}" == "Cancel" ]] && return 0

    if [[ "${fs_type}" == "btrfs" ]]; then
        log_info "Unmounting BTRFS subvolumes recursively..."
        umount -R /mnt 2>/dev/null || { log_error "Failed to unmount /mnt recursively"; return 1; }
    else
        log_info "Unmounting /mnt for filesystem check..."
        umount /mnt 2>/dev/null || { log_error "Failed to unmount /mnt — something is using it"; return 1; }
    fi

    case "${fs_type}" in
        ext4)
            if [[ "${method}" == Safe* ]]; then fsck.ext4 -p "${root_part}" || log_warn "fsck reported errors (safe mode)"
            else fsck.ext4 -f -y "${root_part}" || log_warn "fsck reported errors (destructive mode)"; fi ;;
        btrfs)
            if [[ "${method}" == Safe* ]]; then btrfs check "${root_part}" || log_warn "btrfs check found issues"
            else
                log_warn "btrfs check --repair can make corruption worse."
                tui_yesno "DANGER" "Really run btrfs check --repair?" && btrfs check --repair "${root_part}" || true
            fi ;;
        xfs)
            if [[ "${method}" == Safe* ]]; then xfs_repair -n "${root_part}" || log_warn "xfs_repair -n found issues"
            else xfs_repair "${root_part}" || log_warn "xfs_repair reported errors"; fi ;;
        *) log_warn "Filesystem repair not supported for ${fs_type}"; mount "${root_part}" /mnt || die "Failed to remount"; return 1 ;;
    esac

    if ! blkid -o value -s TYPE "${root_part}" &>/dev/null; then
        log_error "Filesystem signature missing on ${root_part} after repair — refusing to mount"
        die "Filesystem may be destroyed. Manual recovery required."
    fi

    log_info "Remounting ${root_part} to /mnt..."
    if [[ "${fs_type}" == "btrfs" ]]; then
        mount "${root_part}" /mnt || die "Failed to remount"
        [[ -f /mnt/etc/fstab ]] && mount -a --fstab /mnt/etc/fstab 2>/dev/null || true
    else
        mount "${root_part}" /mnt || die "Failed to remount"
    fi

    if tui_yesno "Post-Repair" "Would you like to run standard system repair (fstab, boot, etc.)?"; then
        repair_detected_issues
    fi
    log_info "Filesystem repair complete."
}

# @brief Run all detected repairs
repair_detected_issues() {
    local fstab_issues=$(state_get FSTAB_ISSUES none)
    local boot_issues=$(state_get BOOT_ISSUES none)
    local pkg_issues=$(state_get PKG_ISSUES none)
    [[ "${fstab_issues}" != "none" ]] && repair_fstab
    [[ "${pkg_issues}"   != "none" ]] && repair_packages
    [[ "${boot_issues}"  != "none" ]] && repair_boot
    log_info "Repair complete."
}