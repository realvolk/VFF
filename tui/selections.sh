# @brief Let the user pick a disk
tui_select_disk() {
    local disk disks=()
    local lsblk_output
    lsblk_output=$(lsblk -dpno NAME,SIZE,MODEL -e 7 2>/dev/null || true)
    while IFS=' ' read -r name size model; do
        [[ -n "${name}" ]] || continue
        disks+=("${name} - ${size} (${model:-Unknown})")
    done <<< "${lsblk_output}"

    if [[ ${#disks[@]} -eq 0 ]]; then
        die "No disks detected"
    fi

    disk=$(tui_menu "Disk Selection" "Choose target drive:" "${disks[@]}") || return 1
    disk="${disk%% *}"
    state_set DISK "${disk}"
}

tui_checklist_from_profile() {
    local title="${1}"
    local choices_var="${2}"
    local state_key="${3}"

    local -a raw=()
    eval "raw=(\"\${${choices_var}[@]}\")"

    if [[ ${#raw[@]} -eq 0 ]]; then
        state_set "${state_key}" ""
        return 0
    fi

    local -a items=()
    local i
    for ((i=0; i<${#raw[@]}; i+=2)); do
        items+=("${raw[$i]}")
    done

    local chosen
    chosen=$(tui_checklist "${title}" "Select ${title,,}:" "${items[@]}") || true
    state_set "${state_key}" "${chosen//$'\n'/ }"
}


# @brief Collect all user configuration before installation
vff_collect_config() {
    tui_select_disk

    tui_select_from_profile "Filesystem" "FS_TYPES"           "FS_TYPE"    "ext4"
    tui_select_from_profile "Kernel"     "KERNEL_CHOICES"     "KERNEL_CHOICE" "linux"
    tui_select_from_profile "Init"       "INIT_SYSTEMS"       "INIT"       "${INIT_SYSTEMS[0]}"
    tui_select_from_profile "Bootloader" "BOOTLOADERS"        "BOOTLOADER" "grub"
    tui_select_from_profile "Desktop"    "DESKTOP_CHOICES"    "WM_DE"      "none"

    if [[ "$(state_get WM_DE)" != "none" ]]; then
        tui_select_from_profile "Display Manager" "DISPLAY_MANAGER_CHOICES" "DISPLAY_MANAGER" "none"
    fi

    tui_select_from_profile "Audio"      "AUDIO_CHOICES"      "AUDIO_STACK" "pipewire"
    tui_select_from_profile "Network"    "NETWORK_STACKS"     "NETWORK_STACK" "networkmanager"
    tui_select_from_profile "Shell"      "SHELL_CHOICES"      "USER_SHELL"   "bash"
    tui_select_from_profile "Privilege"  "PRIV_ESCALATION_CHOICES" "PRIV_ESCALATION" "sudo"
    tui_checklist_from_profile "Extras"  "EXTRA_PACKAGES"     "EXTRAS"

    if tui_yesno "Swap" "Create a swap partition?"; then
        state_set SWAP_ENABLED "yes"
    fi

    if tui_yesno "LUKS" "Encrypt the root partition?"; then
        state_set USE_LUKS "yes"
        local pass=$(tui_password_confirm "LUKS Passphrase" "Enter passphrase:" "Confirm passphrase:")
        state_set LUKS_PASS "${pass}"
    fi

    if tui_yesno "LVM" "Use Logical Volume Management?"; then
        state_set USE_LVM "yes"
    fi

    if tui_yesno "UKI" "Generate a Unified Kernel Image?"; then
        state_set GENERATE_UKI "yes"
    fi

    local input

    input=$(tui_input "Hostname" "Enter system hostname:" "vff")
    state_set HOSTNAME "${input:-vff}"

    input=$(tui_input "Timezone" "Enter timezone (Region/City):" "UTC")
    state_set TIMEZONE "${input:-UTC}"

    input=$(tui_input "Locale" "Enter locale:" "en_US.UTF-8")
    state_set LOCALE "${input:-en_US.UTF-8}"

    input=$(tui_input "Keymap" "Enter keyboard layout:" "us")
    state_set KEYMAP "${input:-us}"

    input=$(tui_input "Username" "Enter username:" "vff")
    state_set USER_NAME "${input:-vff}"

    local pass

    pass=$(tui_password_confirm "User Password" "Enter password:" "Confirm password:")
    state_set USER_PASS "${pass}"

    pass=$(tui_password_confirm "Root Password" "Enter root password:" "Confirm password:")
    state_set ROOT_PASS "${pass}"
}