#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – GPU and VM detection
# No dependencies beyond lspci and /sys

get_gpu_vendor() {
    local vendors
    vendors=$(lspci -nn 2>/dev/null | awk '/VGA|3D/' | grep -oiE 'nvidia|intel|amd')
    if   grep -qi nvidia <<<"${vendors}"; then printf 'nvidia\n'
    elif grep -qi amd    <<<"${vendors}"; then printf 'amd\n'
    elif grep -qi intel  <<<"${vendors}"; then printf 'intel\n'
    else printf 'unknown\n'
    fi
}

get_gpu_info() {
    lspci -nn 2>/dev/null | awk -F': ' '/VGA|3D/ {print $3}' | xargs || true
}

get_pci_id() {
    lspci -n 2>/dev/null | awk '/0300|0302/ {print $3}' | awk -F':' '{print $2}' | head -n1 || true
}

detect_vm() {
    local vm
    vm=$(grep -h -oE 'vmware|qemu|kvm|oracle|virtualbox' /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor 2>/dev/null | head -n1)
    [[ -n "${vm}" ]] && printf '%s\n' "${vm}" || printf 'none\n'
}