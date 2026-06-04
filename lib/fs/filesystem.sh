#!/usr/bin/env bash
set -Eeuo pipefail

create_filesystems() {
    _require_tools mkfs.fat mkfs.ext4 blkid partprobe wipefs
    local disk fs_type swap_enabled
    disk="$(state_get DISK)"
    [[ -b "${disk}" ]] || die "invalid disk: ${disk}"
    fs_type="$(state_get FS_TYPE)"
    swap_enabled="$(state_get SWAP_ENABLED no)"

    local efi_part swap_part root_part

    # Manual mode: use user-specified partitions
    if [[ -n "$(state_get EFI_PART '')" ]]; then
        efi_part="$(state_get EFI_PART)"
        root_part="$(state_get ROOT_PART)"
        if [[ "$(state_get SWAP_ENABLED no)" == "yes" ]]; then
            swap_part="$(state_get SWAP_PART)"
        fi
    else
        efi_part=$(get_partition_name "${disk}" 1)
        if [[ "${swap_enabled}" == 'yes' ]]; then
            swap_part=$(get_partition_name "${disk}" 2)
            root_part=$(get_partition_name "${disk}" 3)
        else
            root_part=$(get_partition_name "${disk}" 2)
        fi
    fi

    [[ -b "${efi_part}" ]] || die "invalid EFI partition: ${efi_part}"
    [[ -b "${root_part}" ]] || die "invalid root partition: ${root_part}"
    [[ "/dev/$(lsblk -no PKNAME "${efi_part}")" == "${disk}" ]] || die "EFI partition does not belong to selected disk"
    if [[ "$(state_get USE_LVM no)" != "yes" ]]; then
        [[ "/dev/$(lsblk -no PKNAME "${root_part}")" == "${disk}" ]] || die "Root partition does not belong to selected disk"
    fi

    case "${fs_type}" in
        btrfs)     command -v mkfs.btrfs >/dev/null || die "mkfs.btrfs not found – install btrfs-progs" ; modprobe btrfs 2>/dev/null || true ;;
        ext4)      command -v mkfs.ext4  >/dev/null || die "mkfs.ext4 not found – install e2fsprogs"  ; modprobe ext4 2>/dev/null || true ;;
        xfs)       command -v mkfs.xfs   >/dev/null || die "mkfs.xfs not found – install xfsprogs"    ; modprobe xfs 2>/dev/null || true ;;
        f2fs)      command -v mkfs.f2fs  >/dev/null || die "mkfs.f2fs not found – install f2fs-tools" ; modprobe f2fs 2>/dev/null || true ;;
        bcachefs)  command -v mkfs.bcachefs >/dev/null || die "mkfs.bcachefs not found – install bcachefs-tools" ; modprobe bcachefs 2>/dev/null || true ;;
        exfat)     command -v mkfs.exfat >/dev/null || die "mkfs.exfat not found – install exfatprogs" ; modprobe exfat 2>/dev/null || true ;;
        zfs)
            command -v zpool >/dev/null || die "zpool command unavailable"
            if ! modprobe zfs 2>/dev/null; then
                log_error "Failed to load ZFS kernel module."
                return 1
            fi ;;
    esac

    log_info "Wiping old filesystem signatures..."
    wipefs -af "${efi_part}" || true
    if [[ "$(state_get USE_LUKS no)" != "yes" ]]; then
        wipefs -af "${root_part}" || true
    fi
    if [[ "${swap_enabled}" == 'yes' ]]; then
        wipefs -af "${swap_part}" || true
    fi

    log_info "Formatting EFI partition..."
    mkfs.fat -F32 "${efi_part}" || die 'Failed to create FAT32 EFI filesystem'
    partprobe "${disk}" || true
    udevadm settle || true
    if ! blkid -o value -s TYPE "${efi_part}" | grep -qi 'vfat'; then
        die "EFI partition ${efi_part} does not have a vfat signature"
    fi

    if [[ "${swap_enabled}" == 'yes' ]]; then
        log_info "Initializing swap..."
        [[ -b "${swap_part}" ]] || die "invalid swap partition: ${swap_part}"
        mkswap "${swap_part}"
        swapon "${swap_part}"
    fi

    local fs_target="${root_part}"

    # LVM path
    if [[ "$(state_get USE_LVM no)" == "yes" ]]; then
        local root_lv="/dev/vg0/root"
        local home_lv="/dev/vg0/home"
        local data_lv="/dev/vg0/data"

        [[ -b "${root_lv}" ]] || die "Root LV not found: ${root_lv} — LVM may not have been set up correctly"

        log_info "LVM detected — creating filesystem on logical volume ${root_lv}..."

        case "${fs_type}" in
            btrfs)     mkfs.btrfs -f "${root_lv}" ;;
            ext4)      mkfs.ext4 -F "${root_lv}" ;;
            xfs)       mkfs.xfs -f -m bigtime=0 "${root_lv}" ;;
            f2fs)      mkfs.f2fs -f -O extra_attr,compression "${root_lv}" ;;
            bcachefs)  mkfs.bcachefs --force --replicas=1 "${root_lv}" ;;
            exfat)     mkfs.exfat -L "root" "${root_lv}" ;;
            zfs)       die "ZFS on LVM is not supported — use ZFS directly on the partition" ;;
            *)         die "Unsupported filesystem for LVM: ${fs_type}" ;;
        esac

        if [[ -b "${home_lv}" ]]; then
            log_info "Creating filesystem on home LV..."
            mkfs.ext4 -F "${home_lv}"
        fi
        if [[ -b "${data_lv}" ]]; then
            log_info "Creating filesystem on data LV..."
            mkfs.ext4 -F "${data_lv}"
        fi

        log_info "LVM filesystem creation complete."
        return 0
    fi

    # Plain LUKS (no LVM)
    if [[ "$(state_get USE_LUKS no)" == "yes" ]]; then
        log_info "Setting up LUKS on ${fs_target}..."
        local luks_pass
        luks_pass="$(state_get LUKS_PASS)"
        printf '%s' "${luks_pass}" | cryptsetup luksFormat --type luks2 "${fs_target}" -
        printf '%s' "${luks_pass}" | cryptsetup luksOpen "${fs_target}" cryptroot -
        fs_target="/dev/mapper/cryptroot"
    fi

    # Format the final target
    case "${fs_type}" in
        btrfs)    mkfs.btrfs -f "${fs_target}" ;;
        ext4)     mkfs.ext4 -F "${fs_target}" ;;
        xfs)      mkfs.xfs -f -m bigtime=0 "${fs_target}" ;;
        f2fs)     mkfs.f2fs -f -O extra_attr,compression "${fs_target}" ;;
        bcachefs) mkfs.bcachefs --force --replicas=1 "${fs_target}" ;;
        exfat)    mkfs.exfat -L "root" "${fs_target}" ;;
        zfs)
            zpool labelclear -f "${fs_target}" 2>/dev/null || true
            wipefs -af "${fs_target}" 2>/dev/null || true
            zpool create -f -o ashift=12 -O compression=zstd -O atime=off -O mountpoint=none zroot "${fs_target}"
            zfs create -o mountpoint=/ zroot/root
            zfs mount zroot/root
            mkdir -p /mnt/boot ;;
    esac

    log_info "Filesystem creation complete."
}