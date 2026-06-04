#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Hardware detection

detect_cpu() {
    local cpu_vendor
    cpu_vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "${cpu_vendor}" in
        GenuineIntel) echo "INTEL" ;;
        AuthenticAMD) echo "AMD" ;;
        *) echo "GENERIC" ;;
    esac
}

detect_net() {
    local net_info result=""
    net_info=$(lspci -mm 2>/dev/null | grep -i 'network\|ethernet')
    if echo "${net_info}" | grep -qi 'intel'; then result+="INTEL "; fi
    if echo "${net_info}" | grep -qi 'realtek'; then result+="REALTEK "; fi
    if echo "${net_info}" | grep -qi 'broadcom'; then result+="BROADCOM "; fi
    if echo "${net_info}" | grep -qi 'atheros'; then result+="ATHEROS "; fi
    if echo "${net_info}" | grep -qi 'virtio'; then result+="VIRTIO "; fi
    [[ -z "${result}" ]] && echo "GENERIC" || echo "${result% }"
}

detect_storage() {
    local storage_info
    storage_info=$(lspci -mm 2>/dev/null | grep -i 'sata\|ide\|scsi\|nvme')
    if echo "${storage_info}" | grep -qi 'virtio'; then echo "VIRTIO"
    elif echo "${storage_info}" | grep -qi 'nvme'; then echo "NVME"
    else echo "ATA"
    fi
}