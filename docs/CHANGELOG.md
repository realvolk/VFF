# Changelog

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