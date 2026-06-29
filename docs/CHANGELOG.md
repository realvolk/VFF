# Changelog

## v2.1.0.0 (2026-06-29) — VFF

### Added
- **BIOS/Legacy boot support** — MBR partitioning, GRUB i386-pc installation, no ESP requirement; all storage modules and bootloader now branch on `VFF_BOOT_MODE` (`lib/fs/partition.sh`, `lib/fs/filesystem.sh`, `lib/fs/mount.sh`, `lib/boot/grub.sh`)
- **Boot mode detection** — `VFF_BOOT_MODE` set to `uefi` or `bios` based on `/sys/firmware/efi`; falls back to `ARTIX_BOOT_MODE` for backward compatibility

## v2.0.0.0 (2026-06-29) — forge-tui & Power User Upgrade

### Changed
- **TUI backend rewritten** — `gum` replaced with `forge-tui` (Rust, ratatui + crossterm); new `tui/forgetui.sh` module; `tui/gum.sh` retained as legacy fallback
- **Service management expanded** — `lib/init/services.sh` now supports systemd alongside openrc, runit, dinit, and s6; added `enable_service_boot`, `disable_service`, `stop_service`, and `restart_service`
- **Build engine upgraded** — `lib/build/` modules now target Portage parity while staying transparent to non-source distros
- **`lib/build/recipe.sh`** — `load_recipe()` now resets `provides` array and guards against recipe variable leaks
- **`lib/build/deps.sh`** — `resolve_deps()` builds a provider map from recipe `provides` arrays; virtual dependencies resolve to concrete packages
- **`lib/build/flags.sh`** — added `use_enable()` for conditional feature flag queries in recipes
- **`lib/build/engine.sh`** — `build_package()` retains binary artifacts in `ARTIFACTS_DIR` after install for cache reuse
- **`lib/build/kconfig.sh`** — `ensure_boot_essentials()` now enables `BLOCK`, `BLK_DEV`, and `USB_HID` as built-in
- **`lib/boot/grub.sh`** — LVM support: `GRUB_PRELOAD_MODULES` config line written, `--modules "part_gpt part_msdos fat lvm dm-mod ext2"` passed to `grub-install` via array to prevent word-splitting; `--removable` flag added
- **`lib/pkg/portage.sh`** — `pkg_bootstrap()` extracts Gentoo stage3 directly; `pkg_install()` uses `--noreplace` to skip already-installed packages
- **`lib/pkg/xbps.sh`** — `pkg_install_local()` now runs `xbps-rindex -a` before installing local packages
- **`lib/net/network.sh`** — init-specific package suffixes (`-openrc`, `-dinit`) now conditional on `VFF_DISTRO`; distros without suffixing (Arch, Gentoo) skip them
- **Profile structure** — all profiles now define `DESKTOP_PACKAGES`, `AUDIO_PACKAGES`, `GPU_PACKAGES`, and `EXTRA_PACKAGES` as associative arrays; post-install hooks standardized

### Added
- **forge-tui TUI backend** — JSON transport via temp files with `chmod 700` directories; `/dev/tty` rendering; newline escaping in all widget calls; `_forge`, `_forge_result`, `_forge_cancelled` helpers
- **Gentoo Linux reference profile** — `profiles/gentoo.sh` with portage backend, stage3 bootstrap, full package category/name format, and OpenRC/systemd init choice
- **Virtual package resolution** — recipes can declare `provides=(virtual/libc)` to satisfy dependencies that request a virtual rather than a concrete package
- **`use_enable()`** — recipe helper returning true if a feature flag was selected; enables `use_enable pulseaudio && configure_flags+=" --enable-pulse"` patterns
- **`enable_service_boot`** — boot-runlevel service enablement for LVM, dmcrypt, device-mapper
- **`disable_service`** — removes services from all runlevels across all init systems
- **`stop_service` / `restart_service`** — runtime service control across all init systems
- **`lib/post/install.sh`** — post-install helpers: `install_desktop`, `install_audio`, `install_gpu_drivers`, `install_extras`, `run_post_install`
- **bcachefs and exfat filesystem support** — added to `create_filesystems` and `mount_filesystems`
- **GRUB `--removable` flag** — EFI fallback path for removable media and firmware that strips boot entries
- **`pkg_install_local`** — all package backends now support installing local package archives

### Fixed
- **LUKS/LVM argument ordering** — `cryptsetup close` called before container setup in both `filesystem.sh` and `mount.sh`; duplicate code fragments removed
- **GRUB + LVM installation failure** — `grub-install` now receives embedded LVM modules so `grub-probe` can resolve `/dev/mapper/` paths inside chroot
- **Portage bootstrap** — `pkg_bootstrap` no longer attempts to install packages during stage3 extraction
- **XBPS local install** — missing `xbps-rindex` indexing added before local package installation
- **Network package naming** — Arch and Gentoo profiles no longer attempt to install init-specific package variants that don't exist

### Security
- **forge-tui temp files** — JSON input/output uses `chmod 700` directories; plaintext passwords never touch disk
- **forge-tui tty isolation** — TUI renders to `/dev/tty` with explicit redirect; no terminal hijacking

---

## v1.0.0.0 (2026-06-21) — Initial Release

### Added
- Modular, distro-agnostic installer framework extracted from ArtixForge v9.0.0.0
- 10 package manager backends: pacman, apt, dnf, zypper, xbps, apk, portage, source, nix, guix
- 4 bootloader modules: GRUB, rEFInd, EFIStub, Limine
- UKI (Unified Kernel Image) support
- Full disk encryption: LUKS with LVM integration
- 6 filesystem support: ext4, btrfs, xfs, f2fs, bcachefs, exfat, zfs
- Source-based build engine: recipes, dependency resolver, build queue, cache, validation
- Hardware detection: CPU, GPU, network, storage, VM detection
- Recovery mode: auto-mount, system detection, fstab/boot/package repair
- State persistence with resume support
- Two TUI backends: native ANSI (zero dependencies) and gum (prettier)
- Reference profiles for Arch Linux and Artix Linux
- Pre-hashed password support (GUI/TUI compatible)
- Conditional `GRUB_ENABLE_CRYPTODISK` (only when /boot is encrypted)
- LUKS pbkdf2 for GRUB compatibility
- Full API documentation in `docs/API.md`