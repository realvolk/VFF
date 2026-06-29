#!/usr/bin/env bash
set -Eeuo pipefail

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

# @brief Partition setup — whole disk or manual
tui_partition_setup() {
    local disk
    disk="$(state_get DISK)"
    [[ -b "${disk}" ]] || die "No disk selected"

    if tui_yesno "Partition Scheme" "Use the entire disk ${disk}?"; then
        # Whole disk: ask about swap
        if tui_yesno "Swap" "Create a swap partition?"; then
            local mem_gib
            mem_gib=$(awk '/MemTotal/ {printf "%d", ($2 / 1024 / 1024) + 1}' /proc/meminfo)
            local default_swap
            if   [[ "${mem_gib}" -le 8 ]]; then default_swap='4G'
            elif [[ "${mem_gib}" -le 16 ]]; then default_swap='8G'
            else default_swap='16G'; fi
            local swap_size
            swap_size=$(tui_input "Swap Size" "Recommended: ${default_swap}" "${default_swap}") || die "Swap size required"
            state_set SWAP_ENABLED "yes"
            state_set SWAP_SIZE "${swap_size}"
        else
            state_set SWAP_ENABLED "no"
            state_set SWAP_SIZE "0"
        fi
        # Clear manual partition selections; auto-partitioning will set them
        state_set EFI_PART ""
        state_set ROOT_PART ""
        state_set SWAP_PART ""
        return 0
    fi

    # Manual partition selection
    local -a parts=()
    while IFS= read -r line; do
        parts+=("$line")
    done < <(lsblk -nlo NAME,SIZE,TYPE,MOUNTPOINT "${disk}" | grep -E 'part' || true)

    if [[ ${#parts[@]} -eq 0 ]]; then
        if tui_yesno "No Partitions" "No partitions found on ${disk}. Launch cfdisk?"; then
            cfdisk "${disk}"
            partprobe "${disk}"
            udevadm settle
            sleep 1
            while IFS= read -r line; do
                parts+=("$line")
            done < <(lsblk -nlo NAME,SIZE,TYPE,MOUNTPOINT "${disk}" | grep -E 'part' || true)
            if [[ ${#parts[@]} -eq 0 ]]; then
                die "Still no partitions found after cfdisk. Cannot continue."
            fi
        else
            die "Cannot continue without partitions"
        fi
    fi

    # Select EFI partition
    local efi_choice
    efi_choice=$(printf '%s\n' "${parts[@]}" | tui_menu "EFI Partition" "Select EFI system partition (>=512 MiB):") || die "EFI partition required"
    local efi_part="/dev/$(echo "${efi_choice}" | awk '{print $1}')"
    state_set EFI_PART "${efi_part}"

    # Select root partition (exclude the one chosen as EFI)
    local -a root_candidates=()
    for part in "${parts[@]}"; do
        [[ "/dev/$(echo "${part}" | awk '{print $1}')" != "${efi_part}" ]] && root_candidates+=("${part}")
    done
    if [[ ${#root_candidates[@]} -eq 0 ]]; then
        die "No partitions available for root (only EFI found). Create more partitions."
    fi
    local root_choice
    root_choice=$(printf '%s\n' "${root_candidates[@]}" | tui_menu "Root Partition" "Select root partition:") || die "Root partition required"
    state_set ROOT_PART "/dev/$(echo "${root_choice}" | awk '{print $1}')"

    # Swap (optional)
    if tui_yesno "Swap" "Do you have a swap partition?"; then
        local swap_choice
        swap_choice=$(printf '%s\n' "${parts[@]}" | tui_menu "Swap Partition" "Select swap partition:") || true
        if [[ -n "${swap_choice}" ]]; then
            state_set SWAP_PART "/dev/$(echo "${swap_choice}" | awk '{print $1}')"
            state_set SWAP_ENABLED "yes"
            state_set SWAP_SIZE "0"
        else
            state_set SWAP_ENABLED "no"
            state_set SWAP_SIZE "0"
        fi
    else
        state_set SWAP_ENABLED "no"
        state_set SWAP_SIZE "0"
    fi
}

# @brief Select a single item from a profile-defined list
tui_select_from_profile() {
    local title="${1}"
    local choices_var="${2}"
    local state_key="${3}"
    local default="${4}"

    local -a raw=()
    eval "raw=(\"\${${choices_var}[@]}\")"

    if [[ ${#raw[@]} -eq 0 ]]; then
        state_set "${state_key}" "${default}"
        return 0
    fi

    local -a items=()
    local i
    for ((i=0; i<${#raw[@]}; i+=2)); do
        [[ -n "${raw[$i]}" ]] && items+=("${raw[$i]}")
    done

    local chosen
    chosen=$(tui_menu "${title}" "Select ${title,,}:" "${items[@]}") || chosen="${default}"
    state_set "${state_key}" "${chosen%% *}"
}

# @brief Select multiple items from a profile-defined checklist
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
        [[ -n "${raw[$i]}" ]] && items+=("${raw[$i]}")
    done

    local chosen
    chosen=$(tui_checklist "${title}" "Select ${title,,}:" "${items[@]}") || true
    state_set "${state_key}" "${chosen//$'\n'/ }"
}

# @brief Collect all user configuration before installation
vff_collect_config() {
    tui_select_disk
    tui_partition_setup

    # LUKS and LVM before filesystem selection (they affect available options)
    if tui_yesno "LUKS" "Encrypt the root partition?"; then
        state_set USE_LUKS "yes"
        local pass
        pass=$(tui_password_confirm "LUKS Passphrase" "Enter passphrase:" "Confirm passphrase:")
        state_set LUKS_PASS "${pass}"

        if tui_yesno "LUKS Keyfile" "Use a keyfile to avoid typing your password twice at boot?"; then
            state_set LUKS_KEYFILE "yes"
        else
            state_set LUKS_KEYFILE "no"
        fi
    else
        state_set USE_LUKS "no"
    fi

    if tui_yesno "LVM" "Use Logical Volume Management?"; then
        state_set USE_LVM "yes"
    else
        state_set USE_LVM "no"
    fi

    tui_select_from_profile "Filesystem" "FS_TYPES"           "FS_TYPE"    "ext4"
    tui_select_from_profile "Kernel"     "KERNEL_CHOICES"     "KERNEL_CHOICE" "linux"
    tui_select_from_profile "Init"       "INIT_SYSTEMS"       "INIT"       "${INIT_SYSTEMS[0]:-openrc}"
    tui_select_from_profile "Bootloader" "BOOTLOADERS"        "BOOTLOADER" "grub"

    if [[ "$(state_get ARTIX_BOOT_MODE uefi)" != "bios" ]]; then
        if tui_yesno "UKI" "Generate a Unified Kernel Image?"; then
            state_set GENERATE_UKI "yes"
        else
            state_set GENERATE_UKI "no"
        fi
    else
        state_set GENERATE_UKI "no"
    fi

    tui_select_from_profile "Desktop"    "DESKTOP_CHOICES"    "WM_DE"      "none"

    if [[ "$(state_get WM_DE)" != "none" ]]; then
        tui_select_from_profile "Display Manager" "DISPLAY_MANAGER_CHOICES" "DISPLAY_MANAGER" "none"
    else
        state_set DISPLAY_MANAGER "none"
    fi

    tui_select_from_profile "Audio"      "AUDIO_CHOICES"      "AUDIO_STACK" "pipewire"
    tui_select_from_profile "Network"    "NETWORK_STACKS"     "NETWORK_STACK" "networkmanager"
    tui_select_from_profile "Shell"      "SHELL_CHOICES"      "USER_SHELL"   "bash"
    tui_select_from_profile "Privilege"  "PRIV_ESCALATION_CHOICES" "PRIV_ESCALATION" "sudo"
    tui_checklist_from_profile "Extras"  "EXTRA_PACKAGES"     "EXTRAS"

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