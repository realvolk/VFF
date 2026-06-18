#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – System detection for recovery mode
# Uses pkg_query from the loaded package backend.
readonly ROOT="/mnt"

# @brief Detect installed init system by checking binaries
detect_init() {
    if [[ -x "${ROOT}/usr/bin/runit" ]]; then state_set INIT runit
    elif [[ -x "${ROOT}/usr/bin/dinit" ]]; then state_set INIT dinit
    elif [[ -x "${ROOT}/usr/bin/s6-rc" ]]; then state_set INIT s6
    elif [[ -x "${ROOT}/usr/bin/openrc" ]]; then state_set INIT openrc
    else state_set INIT openrc; fi
}

# @brief Detect root filesystem type
detect_filesystem() {
    local fs="$(findmnt -no FSTYPE "${ROOT}" 2>/dev/null || true)"
    state_set FS_TYPE "${fs:-ext4}"
}

# @brief Check for ZFS installation
detect_zfs() {
    if pkg_query zfs-utils || pkg_query zfs-dkms; then
        state_set FS_TYPE zfs
    fi
}

# @brief Detect LVM usage
detect_lvm() {
    if [[ -f "${ROOT}/etc/lvm/lvm.conf" ]] || pkg_query lvm2; then
        state_set USE_LVM yes
    else
        state_set USE_LVM no
    fi
}

# @brief Identify the bootloader from filesystem artifacts
detect_bootloader() {
    if [[ -d "${ROOT}/boot/grub" ]] || [[ -f "${ROOT}/boot/grub/grub.cfg" ]]; then
        state_set BOOTLOADER grub
    elif [[ -d "${ROOT}/boot/EFI/refind" ]] || [[ -f "${ROOT}/boot/refind_linux.conf" ]]; then
        state_set BOOTLOADER refind
    elif [[ -f "${ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI" ]] || [[ -f "${ROOT}/boot/limine.conf" ]] || [[ -f "${ROOT}/boot/efi/limine.conf" ]]; then
        state_set BOOTLOADER limine
    else
        state_set BOOTLOADER efistub
    fi
}

# @brief Detect UKI presence
detect_uki() {
    if [[ -f "${ROOT}/boot/efi/EFI/Artix/linux-custom.efi" ]] || \
       compgen -G "${ROOT}/boot/efi/EFI/Linux/"*.efi >/dev/null 2>&1 || \
       grep -qE 'default_uki|uki_output' "${ROOT}/etc/mkinitcpio.d/"*.preset 2>/dev/null; then
        state_set GENERATE_UKI yes
    else
        state_set GENERATE_UKI no
    fi
}

# @brief Detect kernel version using tiered priority
detect_kernel() {
    if [[ -f "${ROOT}/boot/vmlinuz-linux-custom" ]]; then
        state_set KERNEL_CHOICE linux-custom
        return 0
    fi

    local -a tier1=(
        linux-cachyos-bmq linux-cachyos-eevdf linux-cachyos-rt-bore
        linux-cachyos-hardened linux-cachyos-lts linux-cachyos-server
        linux-cachyos-deckify linux-cachyos-bore linux-cachyos
        linux-xanmod-x64v4 linux-xanmod-x64v3 linux-xanmod-x64v2 linux-xanmod
        linux-bazzite-bin linux-tkg linux-tkg-bore
    )
    for k in "${tier1[@]}"; do
        if pkg_query "${k}"; then
            state_set KERNEL_CHOICE "${k#linux-}"
            return 0
        fi
    done

    local -a tier2=(linux-zen linux-lts linux-hardened linux-libre linux)
    for k in "${tier2[@]}"; do
        if pkg_query "${k}"; then
            state_set KERNEL_CHOICE "${k#linux-}"
            return 0
        fi
    done

    if [[ -d "${ROOT}/opt/linux-tkg" ]]; then
        state_set KERNEL_CHOICE tkg
        return 0
    fi

    local kver
    kver=$(ls -1 "${ROOT}/boot/vmlinuz-"* 2>/dev/null | sort -V | head -n1 | sed 's/.*vmlinuz-//')
    case "${kver}" in
        *cachyos*)  state_set KERNEL_CHOICE linux-cachyos ;;
        *zen*)      state_set KERNEL_CHOICE linux-zen ;;
        *lts*)      state_set KERNEL_CHOICE linux-lts ;;
        *hardened*) state_set KERNEL_CHOICE linux-hardened ;;
        *)          state_set KERNEL_CHOICE linux ;;
    esac
}

# @brief Detect desktop environment
detect_desktop() {
    local -A de_map=(
        [mangowm]=mango [hyprland]=hyprland [niri]=niri [sway]=sway
        [xfce4]=xfce4 [lxqt]=lxqt [i3-wm]=i3wm [dwm]=dwm [vxwm]=vxwm
        [icewm]=icewm [sonicde-meta]=sonicde [plasma-desktop]=kde
    )
    for pkg in "${!de_map[@]}"; do
        if pkg_query "${pkg}"; then
            state_set WM_DE "${de_map[$pkg]}"
            if [[ "${de_map[$pkg]}" == "kde" ]]; then
                if pkg_query kde-applications; then
                    state_set KDE_PROFILE full
                elif pkg_query dolphin; then
                    state_set KDE_PROFILE minimal
                else
                    state_set KDE_PROFILE desktop
                fi
            fi
            return 0
        fi
    done
    if pkg_query lxde-common || pkg_query lxde; then
        state_set WM_DE lxde
    elif [[ -f "${ROOT}/usr/local/bin/vxwm" ]]; then
        state_set WM_DE vxwm
    else
        state_set WM_DE none
    fi
}

# @brief Detect display manager
detect_display_manager() {
    if pkg_query sonic-login-manager; then
        state_set DISPLAY_MANAGER soniclogin
    elif pkg_query sddm; then
        state_set DISPLAY_MANAGER sddm
    elif pkg_query lightdm; then
        state_set DISPLAY_MANAGER lightdm
    else
        state_set DISPLAY_MANAGER none
    fi
}

# @brief Detect X stack (xlibre/Xorg/Wayland)
detect_xstack() {
    if pkg_query xlibre-xserver; then
        state_set X_STACK xlibre
    elif pkg_query xorg-server; then
        state_set X_STACK xorg
    else
        state_set X_STACK none
    fi
}

# @brief Detect seat manager (seatd vs elogind)
detect_seat_manager() {
    if pkg_query seatd; then
        state_set SEAT_MANAGER seatd
    else
        state_set SEAT_MANAGER elogind
    fi
}

# @brief Detect active network stack
detect_network_stack() {
    if pkg_query networkmanager; then
        state_set NETWORK_STACK networkmanager
    elif pkg_query connman; then
        state_set NETWORK_STACK connman
    elif pkg_query dhcpcd || pkg_query iwd; then
        state_set NETWORK_STACK dhcpcd+iwd
    else
        state_set NETWORK_STACK none
    fi
}

# @brief Detect audio stack
detect_audio_stack() {
    if pkg_query pipewire; then
        state_set AUDIO_STACK pipewire
    elif pkg_query pulseaudio; then
        state_set AUDIO_STACK pulseaudio
    else
        state_set AUDIO_STACK none
    fi
}

# @brief Detect CPU microcode package
detect_ucode() {
    if pkg_query intel-ucode; then
        state_set CPU_UCODE intel
    elif pkg_query amd-ucode; then
        state_set CPU_UCODE amd
    else
        state_set CPU_UCODE none
    fi
}

# @brief Detect user shell from /etc/passwd
detect_user_shell() {
    local shell
    shell="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $7; exit}' "${ROOT}/etc/passwd" 2>/dev/null || true)"
    shell="${shell##*/}"
    case "${shell}" in bash|zsh|fish) ;; *) shell='bash' ;; esac
    state_set USER_SHELL "${shell}"
}

# @brief Detect installed extra packages
detect_extras() {
    local extras=()
    local -a pkg_list=(
        git flatpak fastfetch firewalld bluez fzf zoxide starship eza btop htop nvtop tmux
        nano vim neovim micro helix firefox chromium qutebrowser ranger lf nnn thunar
        alacritty kitty foot mpv feh
    )
    for pkg in "${pkg_list[@]}"; do
        pkg_query "${pkg}" && extras+=("${pkg}")
    done
    if pkg_query zram-generator || pkg_query zramen; then extras+=(zram-tools); fi
    state_set EXTRAS "${extras[*]}"
}

# @brief Detect if Arch repositories are enabled
detect_repositories() {
    if grep -Eq '^\[(core|extra|multilib)\]' "${ROOT}/etc/pacman.conf" 2>/dev/null; then
        state_set ENABLE_ARCH_REPOS yes
    else
        state_set ENABLE_ARCH_REPOS no
    fi
    if grep -q '^\[chaotic-aur\]' "${ROOT}/etc/pacman.conf" 2>/dev/null; then
        state_set HAS_CHAOTIC yes
    else
        state_set HAS_CHAOTIC no
    fi
}

# @brief Detect primary username
detect_username() {
    local user
    user="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' "${ROOT}/etc/passwd" 2>/dev/null || true)"
    [[ -n "${user}" ]] || user='vff'
    state_set USER_NAME "${user}"
}

# @brief Detect LUKS encryption by walking device mapper
detect_luks() {
    local source parent
    source="$(findmnt -no SOURCE "${ROOT}" 2>/dev/null || true)"
    [[ -n "${source}" ]] || return 0
    local check_dev="${source}"
    while [[ -n "${check_dev}" ]]; do
        if cryptsetup isLuks "${check_dev}" &>/dev/null; then
            state_set USE_LUKS yes; return 0
        fi
        parent="$(lsblk -no PKNAME "${check_dev}" 2>/dev/null || true)"
        [[ -n "${parent}" ]] && check_dev="/dev/${parent}" || break
    done
    for mapper_dev in /dev/mapper/*; do
        [[ -b "${mapper_dev}" ]] || continue
        if cryptsetup isLuks "${mapper_dev}" &>/dev/null; then
            state_set USE_LUKS yes; return 0
        fi
    done
    state_set USE_LUKS no
}

# @brief Detect installation disk from mountpoint and fstab
detect_disk() {
    local source pkname disk candidate
    source="$(findmnt -no SOURCE "${ROOT}" 2>/dev/null || true)"
    [[ -n "${source}" ]] || return 0
    if [[ "${source}" == /dev/mapper/* ]]; then
        pkname="$(lsblk -no PKNAME "${source}" 2>/dev/null || true)"
        [[ -n "${pkname}" ]] && source="/dev/${pkname}"
    fi
    candidate="${source}"
    while [[ -n "${candidate}" ]]; do
        disk="$(lsblk -no PKNAME "${candidate}" 2>/dev/null || true)"
        if [[ -z "${disk}" ]]; then break; fi
        candidate="/dev/${disk}"
    done
    if [[ -b "${candidate}" ]]; then
        state_set DISK "${candidate}"; log_info "Detected installation disk: ${candidate}"; return 0
    fi
    local fstab_root
    fstab_root="$(awk '$2 == "/" {print $1}' "${ROOT}/etc/fstab" 2>/dev/null | head -n1)"
    if [[ "${fstab_root}" == UUID=* ]]; then
        candidate="$(blkid -U "${fstab_root#UUID=}" 2>/dev/null || true)"
        [[ -b "${candidate}" ]] && { state_set DISK "${candidate}"; log_info "Detected disk from fstab UUID: ${candidate}"; return 0; }
    fi
    log_warn "Could not auto-detect installation disk."
    if tui_yesno "Disk Detection" "Select installation disk manually?"; then
        tui_select_disk
    else
        die "Cannot continue without a valid installation disk."
    fi
}

# @brief Detect display protocol (Wayland/X11)
detect_display_protocol() {
    if [[ -d "${ROOT}/usr/share/wayland-sessions" ]]; then
        state_set DISPLAY_PROTOCOL wayland
    elif [[ -d "${ROOT}/usr/share/xsessions" ]]; then
        state_set DISPLAY_PROTOCOL x11
    fi
}

# @brief Detect NVIDIA GPU driver
detect_nvidia() {
    if pkg_query nvidia || pkg_query nvidia-dkms || pkg_query nvidia-open; then
        state_set GPU_DRIVER nvidia
    fi
}

# @brief Detect virtualization guest tools
detect_virtualization() {
    if pkg_query qemu-guest-agent; then state_set VM_GUEST qemu
    elif pkg_query virtualbox-guest-utils; then state_set VM_GUEST virtualbox
    elif pkg_query open-vm-tools; then state_set VM_GUEST vmware
    else state_set VM_GUEST none; fi
}

# @brief Read hostname from target
detect_hostname() {
    local hostname='vff'
    [[ -f "${ROOT}/etc/hostname" ]] && hostname="$(tr -d '[:space:]' < "${ROOT}/etc/hostname")"
    state_set HOSTNAME "${hostname}"
}

# @brief Detect coreutils implementation (GNU/BusyBox/uutils)
detect_coreutils() {
    if pkg_query busybox && [[ "$(readlink "${ROOT}/usr/bin/ls" 2>/dev/null)" == *"busybox"* ]]; then
        state_set COREUTILS busybox
    elif pkg_query uutils-coreutils; then
        state_set COREUTILS uutils
    else
        state_set COREUTILS gnu
    fi
}

# @brief Detect if Power User mode was used
detect_poweruser() {
    if [[ -f "${ROOT}/etc/vff/world.txt" ]] || [[ -f "${ROOT}/usr/local/bin/vff-build" ]]; then
        state_set POWER_USER yes
        if [[ -f "${ROOT}/etc/vff/world.txt" ]]; then
            local pkgs=$(tr '\n' ' ' < "${ROOT}/etc/vff/world.txt")
            state_set POWERUSER_PACKAGES "${pkgs}"
        fi
    else
        state_set POWER_USER no
    fi
}

# @brief Detect privilege escalation method (sudo/doas)
detect_priv_escalation() {
    if pkg_query doas && [[ -f "${ROOT}/etc/doas.conf" ]]; then
        state_set PRIV_ESCALATION doas
    elif pkg_query sudo; then
        state_set PRIV_ESCALATION sudo
    else
        state_set PRIV_ESCALATION none
    fi
}

# @brief Determine how far the installation progressed
detect_install_stage() {
    local status=""
    [[ -f "${ROOT}/etc/fstab" ]] && status+="fstab "
    [[ -x "${ROOT}/usr/bin/bash" ]] && status+="basestrap "
    [[ -f "${ROOT}/boot/grub/grub.cfg" ]] && status+="grub "
    [[ -f "${ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI" ]] && status+="limine "
    [[ -f "${ROOT}/boot/refind_linux.conf" ]] && status+="refind "
    compgen -G "${ROOT}/boot/efi/EFI/Linux/"*.efi >/dev/null 2>&1 && status+="uki "
    [[ -d "${ROOT}/home" ]] && status+="home "
    [[ -f "${ROOT}/etc/hostname" ]] && status+="hostname "
    [[ -f "${ROOT}/etc/locale.conf" ]] && status+="locale "
    [[ -f "${ROOT}/root/.vff-post-complete" ]] && status+="post-complete "
    if pkg_query xfce4 || pkg_query plasma-desktop || pkg_query hyprland; then status+="desktop "; fi
    [[ -z "${status}" ]] && status="minimal (base system only)"
    state_set RECOVERY_STATUS "${status}"
}

# @brief Verify fstab integrity
detect_fstab_health() {
    if [[ -f "${ROOT}/etc/fstab" ]]; then
        local issues=""
        while IFS= read -r line; do
            [[ -z "${line}" || "${line}" == \#* ]] && continue
            local device=$(echo "${line}" | awk '{print $1}')
            if [[ "${device}" == UUID=* ]]; then
                local uuid="${device#UUID=}"
                if ! blkid -U "${uuid}" &>/dev/null; then
                    issues+="missing-uuid:${uuid} "
                fi
            fi
        done < "${ROOT}/etc/fstab"
        state_set FSTAB_ISSUES "${issues:-none}"
    else
        state_set FSTAB_ISSUES "missing"
    fi
}

# @brief Check boot health (kernel, initramfs, init symlink, bootloader config)
detect_boot_health() {
    local issues=""
    if [[ -d "${ROOT}/boot" ]]; then
        if ! ls "${ROOT}/boot/vmlinuz-"* &>/dev/null; then issues+="no-kernel "; fi
        if ! ls "${ROOT}/boot/initramfs-"*.img &>/dev/null; then issues+="no-initramfs "; fi
    else
        issues+="no-boot-dir "
    fi
    if [[ ! -e "${ROOT}/sbin/init" ]]; then issues+="no-init "; fi
    if [[ "$(state_get GENERATE_UKI no)" == "yes" ]]; then
        if ! compgen -G "${ROOT}/boot/efi/EFI/Linux/"*.efi >/dev/null 2>&1 && \
           ! [[ -f "${ROOT}/boot/efi/EFI/Artix/linux-custom.efi" ]]; then
            issues+="no-uki "
        fi
    fi
    if command -v efibootmgr &>/dev/null; then
        if ! efibootmgr 2>/dev/null | grep -qi 'Artix\|Linux\|VFF'; then
            issues+="no-efi-entry "
        fi
    fi
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        local cmdline_missing=0 bootloader="$(state_get BOOTLOADER grub)"
        case "${bootloader}" in
            grub)
                [[ -f "${ROOT}/boot/grub/grub.cfg" ]] && grep -q 'cryptdevice=' "${ROOT}/boot/grub/grub.cfg" || cmdline_missing=1 ;;
            limine)
                local conf="${ROOT}/boot/efi/limine.conf"; [[ -f "${ROOT}/boot/limine.conf" ]] && conf="${ROOT}/boot/limine.conf"
                [[ -f "${conf}" ]] && grep -q 'cryptdevice=' "${conf}" || cmdline_missing=1 ;;
            refind)
                [[ -f "${ROOT}/boot/refind_linux.conf" ]] && grep -q 'cryptdevice=' "${ROOT}/boot/refind_linux.conf" || cmdline_missing=1 ;;
        esac
        [[ ${cmdline_missing} -eq 1 ]] && issues+="missing-cryptdevice "
        if [[ -f "${ROOT}/etc/mkinitcpio.conf" ]]; then
            grep -q 'encrypt' "${ROOT}/etc/mkinitcpio.conf" || issues+="missing-encrypt-hook "
        fi
    fi
    state_set BOOT_ISSUES "${issues:-none}"
}

# @brief Check package manager health
detect_pkg_health() {
    local issues=""
    if [[ -f "${ROOT}/var/lib/pacman/db.lck" ]] || [[ -f "${ROOT}/var/lib/dpkg/lock-frontend" ]] || [[ -f "${ROOT}/var/lib/zypp/lock" ]]; then
        issues+="stale-lock "
    fi
    if ! pkg_query base 2>/dev/null && ! pkg_query base-system 2>/dev/null && ! pkg_query filesystem 2>/dev/null; then
        issues+="base-missing "
    fi
    if command -v pacman &>/dev/null; then
        local broken=$(pacman --root "${ROOT}" -Qk 2>/dev/null | grep ': missing' | cut -d: -f1 | sort -u | tr '\n' ' ') || true
        if [[ -n "${broken}" ]]; then
            local count=$(echo "${broken}" | wc -w)
            issues+="broken-pkgs:${count} "
            state_set BROKEN_PACKAGES "${broken}"
        fi
    fi
    state_set PKG_ISSUES "${issues:-none}"
}

# @brief Reconstruct full system state from mounted installation
reconstruct_state_from_system() {
    validate_recovery_root
    detect_disk; detect_init; detect_filesystem; detect_zfs; detect_lvm
    detect_bootloader; detect_uki; detect_kernel; detect_desktop
    detect_display_manager; detect_xstack; detect_seat_manager
    detect_network_stack; detect_audio_stack; detect_ucode
    detect_user_shell; detect_extras; detect_repositories; detect_username
    detect_luks; detect_display_protocol; detect_nvidia; detect_virtualization
    detect_hostname; detect_coreutils; detect_poweruser; detect_priv_escalation
    detect_install_stage; detect_fstab_health; detect_boot_health; detect_pkg_health
    state_save
}

# @brief Verify that /mnt is a valid recovery root
validate_recovery_root() {
    mountpoint -q "${ROOT}" || die "recovery root is not mounted: ${ROOT}"
    [[ -d "${ROOT}/etc" ]] || die "missing ${ROOT}/etc"
}

# @brief Return a human-readable status summary
recovery_get_status() {
    local status=""
    status+="Install stage: $(state_get RECOVERY_STATUS unknown)"$'\n'
    status+="Filesystem: $(state_get FS_TYPE ext4)"$'\n'
    status+="LVM: $(state_get USE_LVM no)"$'\n'
    status+="LUKS: $(state_get USE_LUKS no)"$'\n'
    status+="UKI: $(state_get GENERATE_UKI no)"$'\n'
    status+="Bootloader: $(state_get BOOTLOADER unknown)"$'\n'
    status+="Kernel: $(state_get KERNEL_CHOICE unknown)"$'\n'
    status+="Power User: $(state_get POWER_USER no)"$'\n'
    status+="Coreutils: $(state_get COREUTILS unknown)"$'\n'
    local fstab_issues=$(state_get FSTAB_ISSUES none)
    local boot_issues=$(state_get BOOT_ISSUES none)
    local pkg_issues=$(state_get PKG_ISSUES none)
    [[ "${fstab_issues}" != "none" ]] && status+=$'\n'"FSTAB issues: ${fstab_issues}"
    [[ "${boot_issues}" != "none" ]] && status+=$'\n'"Boot issues: ${boot_issues}"
    [[ "${pkg_issues}" != "none" ]] && status+=$'\n'"Package issues: ${pkg_issues}"
    printf '%s\n' "${status}"
}