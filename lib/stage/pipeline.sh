#!/usr/bin/env bash
set -Eeuo pipefail

# Volk's Forge Framework – Pipeline orchestration
# Set VFF_STAGES before sourcing: VFF_STAGES=(preflight storage base chroot post finalize)

# @brief Run a pipeline stage if not already completed
vff_run_stage() {
    local stage_name="${1}"
    local stage_func="${2}"

    if stage_should_skip "${stage_name}"; then
        return 0
    fi

    log_info "Running stage: ${stage_name}"
    if ! "${stage_func}"; then
        die "Stage '${stage_name}' failed"
    fi
    stage_mark_done "${stage_name}"
}

# @brief Run the full installation pipeline with resume support
vff_run_pipeline() {
    vff_run_stage "preflight"   vff_preflight
    vff_run_stage "preflight_tools" vff_preflight_tools
    vff_run_stage "partition"   partition_disk
    vff_run_stage "filesystem"  create_filesystems
    vff_run_stage "mount"       mount_filesystems
    vff_run_stage "bootstrap"   vff_bootstrap_stage
    vff_run_stage "system"      configure_system
    vff_run_stage "users"       configure_users
    vff_run_stage "network"     "${VFF_NETWORK_HOOK:-:}"
    vff_run_stage "post"        run_post_install
    vff_run_stage "bootloader"  configure_grub
    vff_run_stage "finalize"    "${VFF_FINALIZE_HOOK:-:}"
}

vff_bootstrap_stage() {
    pkg_bootstrap "${BASE_PACKAGES[@]}"
}