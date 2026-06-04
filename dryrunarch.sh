#!/usr/bin/env bash
# test_vff.sh — source everything, verify functions exist, then exit
set -Eeuo pipefail
VFF_DIR="$(pwd)"

source "${VFF_DIR}/lib/core.sh"
vff_source_all
source "${VFF_DIR}/profiles/arch.sh"

# Verify every expected function exists
declare -a required=(
    log_info die require_root require_efi require_internet
    state_get state_set state_save state_load
    pkg_bootstrap pkg_install pkg_chroot pkg_query pkg_repo_setup pkg_lock_clean
    partition_disk create_filesystems mount_filesystems
    configure_system configure_users
    configure_grub setup_arch_network run_post_install arch_post_install
    vff_collect_config tui_menu tui_yesno tui_input tui_select_disk
    build_package resolve_deps validate_recipe load_recipe
    get_gpu_vendor detect_cpu detect_net detect_storage
    enable_service service_exists
)

for func in "${required[@]}"; do
    if declare -F "$func" &>/dev/null; then
        echo "  OK: $func"
    else
        echo "  MISSING: $func"
    fi
done

echo "Dry run complete."