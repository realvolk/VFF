#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Build queue
VFF_BUILD_DIR="${VFF_BUILD_DIR:-${VFF_TARGET:-/mnt}/var/cache/vff/build}"
QUEUE_DIR="${VFF_BUILD_DIR:-/var/cache/vff/build}/queue"
mkdir -p "${QUEUE_DIR}"

# @brief Generate a build queue from an ordered list
generate_queue() {
    local -a pkgs=("$@")
    printf '%s\n' "${pkgs[@]}" > "${QUEUE_DIR}/order.txt"
    : > "${QUEUE_DIR}/status.txt"
    for pkg in "${pkgs[@]}"; do
        printf '%s|pending\n' "${pkg}" >> "${QUEUE_DIR}/status.txt"
    done
}

# @brief Return the next pending package
queue_next() {
    grep '|pending$' "${QUEUE_DIR}/status.txt" | head -n1 | cut -d'|' -f1
}

# @brief Mark a package as done or failed
queue_mark() {
    local pkg="${1}" status="${2}"
    sed -i "s/^${pkg}|.*/${pkg}|${status}/" "${QUEUE_DIR}/status.txt"
}

# @brief Return 0 if all packages are processed
queue_all_done() {
    ! grep -q '|pending$' "${QUEUE_DIR}/status.txt" 2>/dev/null
}

# @brief Return the number of remaining packages
queue_remaining() {
    grep -c '|pending$' "${QUEUE_DIR}/status.txt" 2>/dev/null || echo 0
}