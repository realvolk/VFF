#!/usr/bin/env bash
# Volk's Forge Framework – Gentoo Linux profile

# --- Package backend ---
source "${VFF_DIR}/lib/pkg/portage.sh"

DISTRO_NAME="Gentoo Linux"
DISTRO_ID="gentoo"
VFF_BOOTLOADER_ID="Gentoo"

VFF_TARGET="/mnt/gentoo"
VFF_NETWORK_HOOK="gentoo_setup_network"
VFF_FINALIZE_HOOK="gentoo_post_install"
VFF_REQUIRED_TOOLS="sgdisk parted partprobe mount lsblk wipefs mkfs.fat mkfs.ext4"

UKI_SUPPORTED="yes"
UKI_BINARY="ukify"
UKI_PACKAGE="sys-apps/systemd-utils"

# --- Base packages (installed after stage3) ---
BASE_PACKAGES=(
    sys-kernel/gentoo-kernel
    sys-kernel/linux-firmware
    sys-kernel/installkernel
    app-shells/bash
    app-editors/nano
    app-admin/sudo
    dev-vcs/git
    net-misc/curl
    sys-apps/pciutils
    sys-apps/usbutils
    sys-apps/man-db
    sys-process/cronie
    app-admin/sysklogd
    app-portage/gentoolkit
)

# --- Kernel choices ---
KERNEL_CHOICES=(
    "gentoo-kernel"        "Distribution kernel (source, automated)"
    "gentoo-kernel-bin"    "Distribution kernel (binary, precompiled)"
    "gentoo-sources"       "Source kernel (manual config)"
    "gentoo-sources-genkernel" "Source kernel (genkernel automated)"
)

# --- Init systems ---
INIT_SYSTEMS=("openrc" "systemd")

# --- Filesystems ---
FS_TYPES=("ext4" "xfs" "btrfs" "f2fs")

# --- Bootloaders ---
BOOTLOADERS=("grub" "refind" "efistub" "systemd-boot")

# --- Network stacks ---
NETWORK_STACKS=("networkmanager" "dhcpcd+iwd")

# --- Audio choices ---
AUDIO_CHOICES=(
    "pipewire"     "PipeWire"
    "pulseaudio"   "PulseAudio"
    "none"         "No audio"
)

# --- Desktop environments ---
DESKTOP_CHOICES=(
    "gnome"    "GNOME desktop"
    "kde"      "KDE Plasma desktop"
    "xfce"     "XFCE desktop"
    "i3"       "i3 window manager"
    "none"     "No desktop"
)

declare -A DESKTOP_PACKAGES
DESKTOP_PACKAGES=(
    ["gnome"]="gnome-base/gnome gnome-extra/gnome-tweaks gnome-base/gdm"
    ["kde"]="kde-plasma/plasma-meta kde-apps/dolphin kde-apps/konsole x11-misc/sddm"
    ["xfce"]="xfce-base/xfce4-meta xfce-extra/xfce4-goodies x11-misc/lightdm x11-misc/lightdm-gtk-greeter"
    ["i3"]="x11-wm/i3 x11-misc/i3status x11-misc/i3lock x11-misc/dmenu x11-terms/xterm x11-misc/lightdm x11-misc/lightdm-gtk-greeter"
    ["none"]=""
)

# --- Display managers ---
DISPLAY_MANAGER_CHOICES=("gdm" "sddm" "lightdm" "none")

# --- Audio package lists ---
declare -A AUDIO_PACKAGES
AUDIO_PACKAGES=(
    ["pipewire"]="media-video/pipewire media-sound/wireplumber media-sound/alsa-utils media-sound/pavucontrol"
    ["pulseaudio"]="media-sound/pulseaudio media-sound/pulseaudio-alsa media-sound/alsa-utils media-sound/pavucontrol"
    ["none"]=""
)

# --- GPU drivers ---
declare -A GPU_PACKAGES
GPU_PACKAGES=(
    ["nvidia"]="x11-drivers/nvidia-drivers"
    ["intel"]="x11-drivers/xf86-video-intel media-libs/mesa dev-libs/vulkan-intel"
    ["amd"]="x11-drivers/xf86-video-amdgpu media-libs/mesa dev-libs/vulkan-radeon"
    ["vmware"]="app-emulation/open-vm-tools x11-drivers/xf86-video-vmware"
    ["qemu"]="app-emulation/spice-vdagent app-emulation/qemu-guest-agent x11-drivers/xf86-video-qxl"
    ["virtualbox"]="app-emulation/virtualbox-guest-additions"
    ["unknown"]="media-libs/mesa x11-drivers/xf86-video-vesa"
)

# --- Shells ---
SHELL_CHOICES=("bash" "zsh" "fish")

# --- Privilege escalation ---
PRIV_ESCALATION_CHOICES=("sudo" "doas" "none")

# --- Extras ---
declare -A EXTRA_PACKAGES
EXTRA_PACKAGES=(
    ["firefox"]="www-client/firefox"
    ["neovim"]="app-editors/neovim"
    ["alacritty"]="x11-terms/alacritty"
    ["mpv"]="media-video/mpv"
    ["flatpak"]="sys-apps/flatpak"
    ["firewalld"]="net-firewall/firewalld"
    ["git"]="dev-vcs/git"
    ["htop"]="sys-process/htop"
    ["tmux"]="app-misc/tmux"
    ["links"]="www-client/links"
)

# --- Post-install ---
gentoo_post_install() {
    log_info "Running Gentoo post-install hooks..."
    pkg_chroot emerge --sync
    pkg_chroot eselect news read new
    pkg_chroot getuto 2>/dev/null || true
    log_info "Gentoo post-install complete."
}

# --- Network configuration ---
gentoo_setup_network() {
    local stack="${NETWORK_STACK:-networkmanager}" init="${INIT:-openrc}"
    case "${stack}" in
        networkmanager)
            pkg_install net-misc/networkmanager
            enable_service NetworkManager ;;
        dhcpcd+iwd)
            pkg_install net-misc/dhcpcd net-wireless/iwd
            enable_service dhcpcd
            enable_service iwd ;;
    esac
}