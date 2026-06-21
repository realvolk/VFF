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

All backends expose the same six functions. Source the backend for your
target distribution.

| Function | Description |
|----------|-------------|
| `pkg_bootstrap <pkgs...>` | Bootstrap a base system into `$VFF_TARGET` |
| `pkg_install <pkgs...>` | Install packages into `$VFF_TARGET` |
| `pkg_chroot <cmd...>` | Run a command inside the target |
| `pkg_query <pkg>` | Return 0 if a package is installed in the target |
| `pkg_repo_setup` | Configure repositories on the live ISO |
| `pkg_lock_clean` | Remove stale lock files in the target |

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
| `create_filesystems` | Format partitions (ext4, btrfs, xfs, f2fs, bcachefs, exfat, zfs) |

## `lib/fs/mount.sh` — Mounting

| Function | Description |
|----------|-------------|
| `mount_filesystems` | Mount root and EFI partitions with BTRFS subvolume support |

## `lib/init/services.sh` — Service management

| Function | Description |
|----------|-------------|
| `service_exists <name>` | Return 0 if the service exists for the current init system |
| `enable_service <name>` | Enable a service at boot |
| `start_service <name>` | Start a service immediately |

## `lib/boot/grub.sh` — Bootloader

| Function | Description |
|----------|-------------|
| `configure_grub` | Install GRUB for x86_64-efi, generate config |

Set `VFF_BOOTLOADER_ID` before calling to change the boot menu label.

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

## `tui/ansi.sh` — Terminal interface

| Function | Description |
|----------|-------------|
| `tui_title <text>` | Print a styled title bar |
| `tui_msg <title> <body>` | Show a message and wait for Enter |
| `tui_msg_quick <title> <body>` | Show a message without pausing |
| `tui_yesno <title> <body>` | Ask a yes/no question, return 0 for yes |
| `tui_input <title> <body> <default>` | Prompt for text input |
| `tui_password <title> <body>` | Prompt for a hidden password |
| `tui_password_confirm <title> <prompt> <confirm>` | Prompt for password twice, return if they match |
| `tui_menu <title> <body> <items...>` | Show a numbered menu, return the chosen item |
| `tui_checklist <title> <body> <items...>` | Show a multi-select menu, return chosen items |
| `tui_spin <title> <command>` | Run a command with a log message |
| `tui_show_file <title> <file>` | Display a file |

Colours are controlled by `VFF_COLOR_TITLE`, `VFF_COLOR_ACCENT`, `VFF_COLOR_ERROR`, and `VFF_COLOR_SUCCESS` (set before sourcing).

## `tui/gum.sh` — Terminal interface (gum backend)

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

Colours are controlled by `VFF_COLOR_TITLE`, `VFF_COLOR_ACCENT`, `VFF_COLOR_ERROR`, and `VFF_COLOR_SUCCESS` (set before sourcing). Defaults match the ArtixForge purple/green palette. Requires `gum` installed on the system.