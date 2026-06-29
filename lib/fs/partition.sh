#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – GPT/MBR partitioning with optional swap, LUKS, and LVM

partition_disk() {
    _require_tools sgdisk wipefs dd blockdev partprobe cryptsetup pvcreate vgcreate lvcreate
    local disk swap_enabled='no' swap_size='0' boot_mode
    disk="$(state_get DISK)"
    [[ -n "${disk}" ]] || die 'no disk selected'
    [[ -b "${disk}" ]] || die 'invalid disk device'

    boot_mode="${VFF_BOOT_MODE:-${ARTIX_BOOT_MODE:-uefi}}"

    # If manual partitions were set, skip auto-partitioning entirely
    if [[ -n "$(state_get EFI_PART '')" ]] || [[ -n "$(state_get ROOT_PART '')" ]]; then
        log_info "Manual partition layout detected — skipping auto-partitioning"
        return 0
    fi

    swap_enabled="$(state_get SWAP_ENABLED no)"
    swap_size="$(state_get SWAP_SIZE 0)"

    log_info "Preparing disk ${disk}..."
    swapoff -a 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    zpool export -a 2>/dev/null || true
    vgchange -an vg0 2>/dev/null || true
    dmsetup remove_all 2>/dev/null || true

    log_info "Wiping existing signatures..."
    wipefs --all --force "${disk}"
    sgdisk --zap-all "${disk}" 2>/dev/null || true
    dd if=/dev/zero of="${disk}" bs=1M count=32 conv=fsync status=none
    blockdev --rereadpt "${disk}" 2>/dev/null || true

    if [[ "${boot_mode}" == "bios" ]]; then
        log_info "Creating MBR partition layout (BIOS)..."
        parted -s "${disk}" mklabel msdos

        if [[ "${swap_enabled}" == 'yes' && "${swap_size}" != "0" ]]; then
            parted -s "${disk}" mkpart primary linux-swap 1MiB "${swap_size}"
            parted -s "${disk}" mkpart primary "${swap_size}" 100%
        else
            parted -s "${disk}" mkpart primary 1MiB 100%
        fi

        partprobe "${disk}" 2>/dev/null || true
        udevadm settle
        sleep 2

        if [[ "${swap_enabled}" == 'yes' && "${swap_size}" != "0" ]]; then
            [[ -b "$(get_partition_name "${disk}" 1)" ]] || die 'swap partition not created'
            [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'root partition not created'
        else
            [[ -b "$(get_partition_name "${disk}" 1)" ]] || die 'root partition not created'
        fi
    else
        log_info "Creating GPT partition layout (UEFI)..."
        sgdisk -n 1:0:+1024M -t 1:ef00 "${disk}"
        if [[ "${swap_enabled}" == 'yes' && "${swap_size}" != "0" ]]; then
            sgdisk -n 2:0:+"${swap_size}" -t 2:8200 "${disk}"
            sgdisk -n 3:0:0 -t 3:8300 "${disk}"
        else
            sgdisk -n 2:0:0 -t 2:8300 "${disk}"
        fi

        partprobe "${disk}" 2>/dev/null || true
        udevadm settle
        sleep 2
        blockdev --rereadpt "${disk}" 2>/dev/null || true

        [[ -b "$(get_partition_name "${disk}" 1)" ]] || die 'EFI partition not created'
        if [[ "${swap_enabled}" == 'yes' && "${swap_size}" != "0" ]]; then
            [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'swap partition not created'
            [[ -b "$(get_partition_name "${disk}" 3)" ]] || die 'root partition not created'
        else
            [[ -b "$(get_partition_name "${disk}" 2)" ]] || die 'root partition not created'
        fi
    fi

    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        log_info "Setting up LVM..."
        local root_part
        if [[ "${boot_mode}" == "bios" ]]; then
            if [[ "${swap_enabled}" == 'yes' && "${swap_size}" != "0" ]]; then
                root_part=$(get_partition_name "${disk}" 2)
            else
                root_part=$(get_partition_name "${disk}" 1)
            fi
        else
            if [[ "${swap_enabled}" == 'yes' && "${swap_size}" != "0" ]]; then
                root_part=$(get_partition_name "${disk}" 3)
            else
                root_part=$(get_partition_name "${disk}" 2)
            fi
        fi

        if [[ "${boot_mode}" != "bios" ]]; then
            sgdisk -t "$(lsblk -no PARTN "${root_part}" | head -n1)":8e00 "${disk}"
            partprobe "${disk}" 2>/dev/null || true
            udevadm settle
        fi

        local lvm_target="${root_part}"

        if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
            dmsetup remove cryptlvm 2>/dev/null || true
            wipefs -af "${root_part}" || true
            log_info "Formatting LUKS container on ${root_part}..."
            local luks_pass
            luks_pass="$(state_get LUKS_PASS)"
            printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 "${root_part}" -
            log_info "Opening LUKS container..."
            printf '%s' "${luks_pass}" | cryptsetup luksOpen "${root_part}" cryptlvm -
            if [[ ! -b /dev/mapper/cryptlvm ]]; then
                die "LUKS mapper /dev/mapper/cryptlvm not created"
            fi
            lvm_target="/dev/mapper/cryptlvm"
        fi

        pvcreate -ff "${lvm_target}" || die "pvcreate failed"
        vgcreate vg0 "${lvm_target}" || die "vgcreate failed"
        lvcreate -L 20G -n root vg0 || die "lvcreate root failed"
        lvcreate -L 8G -n home vg0 || true
        lvcreate -l 100%FREE -n data vg0 || true
    fi

    log_info "Partitioning complete."
}