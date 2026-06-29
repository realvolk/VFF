# Volk's Forge Framework - Gentoo branch

A distro-agnostic installer construction kit. VFF provides a modular,
well-tested backend, a pluggable terminal interface, and an optional
graphical frontend — everything needed to assemble a custom Linux
installer without rebuilding the plumbing from scratch.

VFF is (not literally) the engine that powered ArtixForge through hundreds of
installations. Every module has been hardened in production before
being extracted into this framework.

## Quick start

```bash
git clone https://github.com/realvolk/VFF.git
```

Source the modules you need and call the functions:

```bash
#!/usr/bin/env bash
source vff/lib/core.sh
source vff/lib/state.sh
source vff/lib/pkg/pacman.sh
source vff/lib/fs/partition.sh
source vff/lib/fs/filesystem.sh
source vff/lib/fs/mount.sh
source vff/lib/system/hostname.sh
source vff/lib/users.sh
source vff/profiles/arch.sh
source vff/tui/ansi.sh # Choice between ansi and gum
#or
source vff/tui/forgetui.sh # Custom-made Rust library

require_root
require_efi
pkg_repo_setup
partition_disk
create_filesystems
mount_filesystems
pkg_bootstrap "${BASE_PACKAGES[@]}"
configure_system
configure_users
```

## Supported package managers

| Backend              | Distros                           |
| -------------------- | --------------------------------- |
| `lib/pkg/pacman.sh`  | Arch, Artix, Manjaro, EndeavourOS |
| `lib/pkg/apt.sh`     | Debian, Ubuntu, Mint, Pop!_OS     |
| `lib/pkg/dnf.sh`     | Fedora, RHEL, CentOS, Rocky, Alma |
| `lib/pkg/zypper.sh`  | openSUSE, SLES                    |
| `lib/pkg/xbps.sh`    | Void Linux                        |
| `lib/pkg/apk.sh`     | Alpine, postmarketOS              |
| `lib/pkg/portage.sh` | Gentoo, Calculate, Funtoo         |
| `lib/pkg/source.sh`  | LFS, custom source-based distros  |
| `lib/pkg/nix.sh`     | NixOS                             |
| `lib/pkg/guix.sh`    | Guix System                       |

## Relationship to ArtixForge

ArtixForge is the reference implementation — a full Artix Linux installer
with Power User mode, Quick Profiles, community recipes, and the gartix
package manager. VFF is the distro-agnostic engine extracted from it.

## License

See [LICENSE](docs/LICENSE).