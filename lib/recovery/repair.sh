#!/usr/bin/env bash
set -Eeuo pipefail

repair_fstab() {
    local issues=$(state_get FSTAB_ISSUES none)
    if [[ "${issues}" == "missing" ]]; then
        if tui_yesno "Repair fstab" "Regenerate fstab?"; then
            fstabgen -U /mnt > /mnt/etc/fstab
            log_info "fstab regenerated."
        fi
    elif [[ "${issues}" != "none" ]]; then
        if tui_yesno "Repair fstab" "Regenerate fstab to fix UUIDs?"; then
            fstabgen -U /mnt > /mnt/etc/fstab
        fi
    fi
}

repair_packages() {
    # distro-agnostic: use pkg_install to reinstall base packages
    local issues=$(state_get PACMAN_ISSUES none)
    if [[ "${issues}" =~ stale-lock ]]; then
        if tui_yesno "Remove lock" "Remove stale package lock?"; then
            pkg_lock_clean
        fi
    fi
    if [[ "${issues}" =~ base-missing ]]; then
        if tui_yesno "Reinstall base" "Reinstall base system?"; then
            pkg_bootstrap "${BASE_PACKAGES[@]}"
        fi
    fi
    if [[ "${issues}" =~ broken-pkgs ]]; then
        if tui_yesno "Repair broken packages" "Reinstall broken packages?"; then
            local broken_list=$(state_get BROKEN_PACKAGES "")
            [[ -n "${broken_list}" ]] && pkg_install ${broken_list}
        fi
    fi
}

repair_uki() {
    [[ "$(state_get GENERATE_UKI no)" == "yes" ]] || return 0
    if ! compgen -G "/mnt/boot/efi/EFI/Linux/"*.efi >/dev/null 2>&1; then
        if tui_yesno "Repair UKI" "Regenerate UKI?"; then
            source "${VFF_DIR}/lib/boot/uki.sh"
            generate_uki "/mnt/boot/efi"
        fi
    fi
}

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
    if [[ "${issues}" =~ no-efi-entry ]]; then
        if tui_yesno "Reinstall bootloader" "Reinstall $(state_get BOOTLOADER)?"; then
            source "${VFF_DIR}/lib/boot/$(state_get BOOTLOADER).sh"
            configure_grub   # or configure_limine, configure_refind, etc.
        fi
    fi
    if [[ "${issues}" =~ no-uki ]]; then repair_uki; fi
    if [[ "${issues}" =~ missing-cryptdevice ]]; then
        if tui_yesno "Repair cmdline" "Regenerate bootloader config?"; then
            source "${VFF_DIR}/lib/boot/$(state_get BOOTLOADER).sh"
            configure_grub   # will regenerate config with correct cmdline
        fi
    fi
    if [[ "${issues}" =~ missing-encrypt-hook ]]; then
        if tui_yesno "Repair hooks" "Add encrypt hook?"; then
            pkg_chroot sed -i '/^HOOKS=/s/\(block\)/\1 encrypt/' /etc/mkinitcpio.conf
            pkg_chroot mkinitcpio -P
        fi
    fi
}

repair_detected_issues() {
    local fstab_issues=$(state_get FSTAB_ISSUES none)
    local boot_issues=$(state_get BOOT_ISSUES none)
    local pkg_issues=$(state_get PACMAN_ISSUES none)

    [[ "${fstab_issues}" != "none" ]] && repair_fstab
    [[ "${pkg_issues}"   != "none" ]] && repair_packages
    [[ "${boot_issues}"  != "none" ]] && repair_boot

    log_info "Repair complete."
}