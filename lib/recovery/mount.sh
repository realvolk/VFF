#!/usr/bin/env bash
set -Eeuo pipefail

recovery_mount_all() {
    local -a luks_parts=()
    local part
    while IFS= read -r part; do
        if cryptsetup isLuks "$part" &>/dev/null; then
            luks_parts+=("$part")
        fi
    done < <(lsblk -n -o PATH)

    if [[ ${#luks_parts[@]} -gt 0 ]]; then
        tui_msg "LUKS Container Found" "Found encrypted partition(s): ${luks_parts[*]}"
        for part in "${luks_parts[@]}"; do
            if tui_yesno "Unlock LUKS" "Unlock ${part}?"; then
                local pass=""
                pass=$(tui_password "LUKS Passphrase" "Enter passphrase for ${part}:") || die "LUKS unlock cancelled"
                printf '%s' "${pass}" | cryptsetup luksOpen "${part}" "crypt_$(basename "${part}")" - || {
                    log_warn "Failed to unlock ${part} – wrong passphrase?"
                    continue
                }
                log_info "Unlocked ${part}"
            fi
        done
    fi

    if command -v vgchange &>/dev/null && vgscan 2>/dev/null | grep -q 'Found volume group'; then
        if tui_yesno "LVM Detected" "Activate LVM volume groups?"; then
            vgchange -ay || log_warn "LVM activation failed"
        fi
    fi

    local root_candidate=""
    for dev in /dev/mapper/vg0-root /dev/mapper/cryptroot /dev/mapper/crypt_sda3 /dev/mapper/crypt_sda2; do
        if [[ -b "${dev}" ]]; then
            root_candidate="${dev}"
            break
        fi
    done

    if [[ -z "${root_candidate}" ]]; then
        for dev in /dev/mapper/*; do
            [[ -b "${dev}" ]] || continue
            local fs_type
            fs_type=$(blkid -o value -s TYPE "${dev}" 2>/dev/null || true)
            if [[ "${fs_type}" =~ ^(ext[234]|xfs|btrfs|f2fs)$ ]]; then
                root_candidate="${dev}"
                break
            fi
        done
    fi

    if [[ -z "${root_candidate}" ]]; then
        die "Could not find a root filesystem. Please mount /mnt manually."
    fi

    log_info "Mounting ${root_candidate} at /mnt..."
    mount "${root_candidate}" /mnt || die "Failed to mount root"

    local esp=""
    for candidate in /dev/sda1 /dev/nvme0n1p1 /dev/vda1; do
        if [[ -b "${candidate}" ]] && blkid -o value -s TYPE "${candidate}" 2>/dev/null | grep -qi 'vfat'; then
            esp="${candidate}"
            break
        fi
    done
    if [[ -n "${esp}" ]]; then
        mkdir -p /mnt/boot/efi
        mount "${esp}" /mnt/boot/efi || log_warn "Failed to mount ESP"
    fi

    mkdir -p /mnt/dev /mnt/proc /mnt/sys
    mount --bind /dev /mnt/dev || true
    mount --bind /proc /mnt/proc || true
    mount --bind /sys /mnt/sys || true

    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /mnt/etc/resolv.conf || true
    fi

    if [[ -d /sys/firmware/efi/efivars ]]; then
        mkdir -p /mnt/sys/firmware/efi
        mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars 2>/dev/null || true
    fi

    log_info "Recovery environment prepared."
}