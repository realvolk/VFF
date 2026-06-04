#!/usr/bin/env bash
set -Eeuo pipefail
VFF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${VFF_DIR}/lib/core.sh"
vff_source_all
source "${VFF_DIR}/profiles/artix.sh"

vff_preflight
pkg_repo_setup
vff_collect_config

partition_disk
create_filesystems
mount_filesystems
pkg_bootstrap "${BASE_PACKAGES[@]}"
configure_system
configure_users
artix_setup_network
run_post_install
configure_grub
artix_post_install

log_info "${DISTRO_NAME} installation complete. Reboot."