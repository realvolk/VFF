# VFF API Reference

Every public function in the framework. Source the relevant module and
call the function. All functions assume `set -Eeuo pipefail`.

---

## `lib/core.sh` — Utilities

| Function | Description |
|----------|-------------|
| `log_info <msg>` | Print an informational message to stderr and the log file |
| `log_warn <msg>` | Print a warning message |
| `log_error <msg>` | Print an error message |
| `die <reason>` | Log an error and exit |
| `require_root` | Exit if not running as root |
| `require_efi` | Exit if not booted in UEFI mode |
| `require_internet` | Exit if no network is available (DNS → HTTPS → ICMP) |
| `command_exists <name>` | Return 0 if the command is on PATH |
| `check_disk_space <gb> <path>` | Warn if less than `<gb>` GB free at `<path>` |
| `retry_command <desc> <cmd...>` | Retry a command up to 3 times with exponential backoff |
| `curl_resume <url> <output>` | Download a file with resume support |
| `get_partition_name <disk> <n>` | Return the partition device node (e.g. `/dev/sda1`) |

## Entrypoints — `entrypoints/`

Entrypoints are thin distro-specific scripts that source the framework, source
a profile, and call the install sequence. The framework provides helper functions
for the common boilerplate.

| Function | Description |
|----------|-------------|
| `vff_source_all` | Source all framework modules in dependency order |
| `vff_preflight` | Run preflight checks (root, internet, tools, disk space) |
| `vff_collect_config` | Collect user configuration via TUI (disk, fs, bootloader, etc.) |

### Entrypoint pattern

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
VFF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${VFF_DIR}/lib/core.sh"
vff_source_all
source "${VFF_DIR}/profiles/<distro>.sh"

vff_preflight
pkg_repo_setup
vff_collect_config

partition_disk
create_filesystems
mount_filesystems
pkg_bootstrap "${BASE_PACKAGES[@]}"
configure_system
configure_users
<profile_network_hook>
run_post_install
configure_grub
<profile_finalize_hook>

log_info "${DISTRO_NAME} installation complete. Reboot."
```

Profile variables VFF_NETWORK_HOOK and VFF_FINALIZE_HOOK name the
functions to call for network setup and post-install finalization.
These are defined in the profile and called in the entrypoint.

## `lib/state.sh` — Configuration state

| Function | Description |
|----------|-------------|
| `state_get <key> <default>` | Read a stored value |
| `state_set <key> <value>` | Store a value persistently |
| `state_save` | Write all state to disk |
| `state_load` | Reload state from disk |
| `stage_mark_done <name>` | Mark a pipeline stage as complete |
| `stage_is_done <name>` | Return 0 if the stage is complete |
| `stage_reset <name>` | Reset a stage |
| `stage_should_skip <name>` | Return 0 if the stage is complete and valid |

## `lib/stage/pipeline.sh` — Pipeline orchestration

| Function | Description |
|----------|-------------|
| `run_pipeline` | Execute each stage function defined in `VFF_STAGES` |

## `lib/pkg/*.sh` — Package management

All backends expose the same seven functions. Source the backend for your
target distribution.

| Function | Description |
|----------|-------------|
| `pkg_bootstrap` | Bootstrap a base system into `$VFF_TARGET` |
| `pkg_install <pkgs...>` | Install packages into `$VFF_TARGET` |
| `pkg_install_local <artifact>` | Install a local package archive |
| `pkg_chroot <cmd...>` | Run a command inside the target |
| `pkg_query <pkg>` | Return 0 if a package is installed in the target |
| `pkg_repo_setup` | Configure repositories on the live ISO |
| `pkg_lock_clean` | Remove stale lock files in the target |

### Available backends

| Backend | File | Distribution |
|---------|------|-------------|
| pacman | `lib/pkg/pacman.sh` | Arch Linux, Artix Linux |
| portage | `lib/pkg/portage.sh` | Gentoo Linux |
| xbps | `lib/pkg/xbps.sh` | Void Linux |
| source | `lib/pkg/source.sh` | Linux From Scratch |
| apt | `lib/pkg/apt.sh` | Debian, Ubuntu |
| dnf | `lib/pkg/dnf.sh` | Fedora |
| zypper | `lib/pkg/zypper.sh` | openSUSE |
| apk | `lib/pkg/apk.sh` | Alpine Linux |
| nix | `lib/pkg/nix.sh` | NixOS |
| guix | `lib/pkg/guix.sh` | Guix System |

### pacman backend variables

Set before sourcing `lib/pkg/pacman.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `CHROOT_CMD` | `arch-chroot` | Chroot binary (`artix-chroot` for Artix) |
| `PACMAN_KEYRING` | `artix` | Keyring to populate (`archlinux` for Arch) |
| `PACMAN_BOOTSTRAP` | `basestrap` | Bootstrap command (`pacstrap` for Arch) |
| `PACMAN_ARCH_SUPPORT` | `no` | Enable Arch repos (Artix only) |

## `lib/fs/partition.sh` — Disk partitioning

| Function | Description |
|----------|-------------|
| `partition_disk` | Create GPT partitions (EFI, optional swap, root) with LVM/LUKS support |

## `lib/fs/filesystem.sh` — Filesystem creation

| Function | Description |
|----------|-------------|
| `create_filesystems` | Format partitions (ext4, btrfs, xfs, f2fs, bcachefs, exfat, zfs) with LVM and LUKS support |

## `lib/fs/mount.sh` — Mounting

| Function | Description |
|----------|-------------|
| `mount_filesystems` | Mount root and EFI partitions with BTRFS subvolume, LVM, LUKS, and ZFS support |

## `lib/init/services.sh` — Service management

Supports openrc, runit, dinit, s6, and systemd.

| Function | Description |
|----------|-------------|
| `service_exists <name>` | Return 0 if the service exists for the current init system |
| `enable_service <name>` | Enable a service at default runlevel |
| `enable_service_boot <name>` | Enable a service at boot runlevel (LVM, dmcrypt, etc.) |
| `disable_service <name>` | Remove a service from all runlevels |
| `start_service <name>` | Start a service immediately |
| `stop_service <name>` | Stop a running service |
| `restart_service <name>` | Stop then start a service |

## `lib/boot/grub.sh` — Bootloader

| Function | Description |
|----------|-------------|
| `configure_grub` | Install GRUB for x86_64-efi with LUKS, LVM, XFS, and UKI support; generates grub.cfg |

Set `VFF_BOOTLOADER_ID` before calling to change the boot menu label.
LVM systems automatically get `--modules "part_gpt part_msdos fat lvm dm-mod ext2"` embedded.
LUKS systems get `GRUB_ENABLE_CRYPTODISK` and `cryptdevice=` cmdline when `/boot` is inside the encrypted container.

## `lib/net/network.sh` — Network

| Function | Description |
|----------|-------------|
| `setup_networking` | Install and enable the selected network stack |

## `lib/system/hostname.sh` — System configuration

| Function | Description |
|----------|-------------|
| `configure_system` | Set hostname, locale, timezone, and keymap |

## `lib/users.sh` — User management

| Function | Description |
|----------|-------------|
| `configure_users` | Create root password, user account, and sudo/doas access |

## `lib/post/install.sh` — Post-install

| Function | Description |
|----------|-------------|
| `install_desktop` | Install the selected desktop environment |
| `install_audio` | Install the selected audio stack |
| `install_gpu_drivers` | Install GPU drivers based on detected vendor |
| `install_extras` | Install user-selected extra packages |
| `run_post_install` | Run all post-install steps |

## `lib/build/engine.sh` — Source build engine

| Function | Description |
|----------|-------------|
| `build_package <recipe>` | Build a package from a recipe through prepare/configure/build/check/package phases |
| `handle_build_failure <recipe> <log> <workdir>` | Interactive failure handler with retry, skip, debug shell, and binary fallback |
| `fetch_sources <recipe>` | Download and verify source files for a recipe |

## `lib/build/recipe.sh` — Recipe loader

| Function | Description |
|----------|-------------|
| `load_recipe <name>` | Load a recipe file and export pkgname, pkgver, sources, depends, makedepends, feature_flags, provides |
| `list_recipes` | Print all available recipes with descriptions |

## `lib/build/flags.sh` — Compilation flags

| Function | Description |
|----------|-------------|
| `load_profile <name>` | Load a compilation profile (default, safe, performance, hardened) |
| `use_enable <flag>` | Return 0 if a feature flag is enabled; for conditional configure flags |
| `apply_pkg_flags` | Apply package-specific CFLAGS/CXXFLAGS/LDFLAGS/MAKEFLAGS overrides |
| `flags_hash` | Return a hash of current compilation flags for cache invalidation |

## `lib/build/deps.sh` — Dependency resolution

| Function | Description |
|----------|-------------|
| `resolve_deps <pkgs...>` | Topological sort of packages with virtual package resolution via `provides` |

## `lib/build/queue.sh` — Build queue

| Function | Description |
|----------|-------------|
| `generate_queue <pkgs...>` | Create a build queue from an ordered list |
| `queue_next` | Return the next pending package |
| `queue_mark <pkg> <status>` | Mark a package as done, failed, or skipped |
| `queue_all_done` | Return 0 if all packages are processed |
| `queue_remaining` | Return the number of pending packages |

## `lib/build/cache.sh` — Artifact cache

| Function | Description |
|----------|-------------|
| `cache_hit <pkgname> <pkgver> <flags_hash>` | Return 0 if a cached artifact with matching flags exists |
| `cache_clean` | Remove obsolete cached packages |

## `lib/build/rebuild.sh` — Rebuild detection

| Function | Description |
|----------|-------------|
| `needs_rebuild <pkgname>` | Return 0 if flags changed or dependencies were updated |

## `lib/build/validate.sh` — Validation

| Function | Description |
|----------|-------------|
| `validate_recipe <name>` | Validate a recipe file (required fields, sources, build/package functions) |
| `validate_system` | Post-build system validation (kernel image, initramfs presence) |

## `lib/build/kconfig.sh` — Kernel configuration

| Function | Description |
|----------|-------------|
| `ensure_boot_essentials` | Enable essential kernel options (block, fs, net, tty) |
| `apply_basic_config` | Apply hardware-detected kernel recommendations |
| `apply_advanced_config` | Apply user-selected kernel options (fs, gpu, net, usb, sound, security, virt, debug, preempt, timer, governor) |

## `lib/hw/gpu.sh` — GPU detection

| Function | Description |
|----------|-------------|
| `get_gpu_vendor` | Print `nvidia`, `amd`, `intel`, or `unknown` |
| `get_gpu_info` | Print human-readable GPU description |
| `get_pci_id` | Print the PCI ID of the first GPU |
| `detect_vm` | Print `qemu`, `vmware`, `virtualbox`, or `none` |

## `lib/hw/cpu.sh` — Hardware detection

| Function | Description |
|----------|-------------|
| `detect_cpu` | Print `INTEL`, `AMD`, or `GENERIC` |
| `detect_net` | Print detected network vendor(s) |
| `detect_storage` | Print `VIRTIO`, `NVME`, or `ATA` |

## `lib/recovery/detect.sh` — Recovery detection

| Function | Description |
|----------|-------------|
| `recovery_detect_install` | Return 0 if an existing installation is found at `$VFF_TARGET` |

## `lib/recovery/mount.sh` — Recovery mounting

| Function | Description |
|----------|-------------|
| `recovery_mount_all` | Auto-detect LUKS, LVM, and filesystems and mount at `$VFF_TARGET` |

## `lib/recovery/repair.sh` — Recovery repair

| Function | Description |
|----------|-------------|
| `repair_detected_issues` | Repair common issues (fstab, initramfs, bootloader) |
| `repair_system` | Full system repair (kernel, initramfs, GRUB, fstab) |
| `repair_filesystem` | Run fsck/xfs_repair/btrfs check on the root filesystem |
| `detect_rootkits` | Run rkhunter scan on the mounted target |
| `untrusted_recovery` | Rootkit hunt and malware scan on mounted target |
| `recovery_get_status` | Return a human-readable status summary of the target system |

## `tui/forgetui.sh` — Terminal interface (forge-tui backend)

| Function | Description |
|----------|-------------|
| `tui_title <text>` | Print a styled title bar |
| `tui_msg <title> <body>` | Show a message and wait for Enter |
| `tui_msg_quick <title> <body>` | Show a message without pausing |
| `tui_yesno <title> <body>` | Ask a yes/no question, return 0 for yes |
| `tui_input <title> <body> <default>` | Prompt for text input |
| `tui_password <title> <body>` | Prompt for a hidden password |
| `tui_password_confirm <title> <prompt> <confirm>` | Prompt for password twice, return if they match |
| `tui_menu <title> <body> <items...>` | Show a menu, return the chosen item |
| `tui_checklist <title> <body> <items...>` | Show a multi-select menu, return chosen items |
| `tui_spin <title> <command>` | Run a command with output logged via `log_info` |
| `tui_show_file <title> <file>` | Display a file with scrollbar and keyboard navigation |

Colours are controlled by `VFF_COLOR_TITLE`, `VFF_COLOR_ACCENT`, `VFF_COLOR_ERROR`, and `VFF_COLOR_SUCCESS` (set before sourcing). Requires `forge-tui` (Rust binary) installed on the system. Uses temp file transport with `chmod 700` directories. All widget calls escape newlines in message strings before JSON construction. Passwords are never written to temp files.

## `tui/gum.sh` — Terminal interface (gum backend, legacy)

| Function | Description |
|----------|-------------|
| `tui_title <text>` | Print a styled title bar using gum |
| `tui_msg <title> <body>` | Show a message with gum formatting, wait for Enter |
| `tui_msg_quick <title> <body>` | Show a message with gum formatting without pausing |
| `tui_yesno <title> <body>` | Ask a yes/no question using gum confirm, return 0 for yes |
| `tui_input <title> <body> <default>` | Prompt for text input using gum input |
| `tui_password <title> <body>` | Prompt for a hidden password using gum input --password |
| `tui_password_confirm <title> <prompt> <confirm>` | Prompt for password twice using gum, return if they match |
| `tui_menu <title> <body> <items...>` | Show a menu using gum choose, return the chosen item |
| `tui_checklist <title> <body> <items...>` | Show a multi-select menu using gum choose --no-limit |
| `tui_spin <title> <command>` | Run a command with a gum spinner and log output |
| `tui_show_file <title> <file>` | Display a file using gum pager |

Same colour variables as forgetui.sh. Requires `gum` installed on the system.