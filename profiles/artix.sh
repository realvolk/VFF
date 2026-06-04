#!/usr/bin/env bash
# Volk's Forge Framework – Artix Linux (generic reference profile)
# Source this after the framework core to configure for Artix.

# --- Package backend ---
CHROOT_CMD="artix-chroot"
PACMAN_KEYRING="artix"
PACMAN_BOOTSTRAP="basestrap"
PACMAN_ARCH_SUPPORT="yes"
source "${VFF_DIR}/lib/pkg/pacman.sh"

# --- Distro identity ---
DISTRO_NAME="Artix Linux"
DISTRO_ID="artix"
VFF_BOOTLOADER_ID="Artix"

# --- Hooks ---
VFF_NETWORK_HOOK="artix_setup_network"
VFF_FINALIZE_HOOK="artix_post_install"
VFF_REQUIRED_TOOLS="sgdisk partprobe mount lsblk wipefs"

# --- UKI support ---
UKI_SUPPORTED="yes"
UKI_BINARY="ukify"
UKI_PACKAGE="eukify"

# --- Base packages ---
BASE_PACKAGES=(
    base base-devel linux linux-firmware linux-headers
    bash vim nano sudo git curl wget
    pciutils usbutils man-db man-pages
)

# --- Kernel choices ---
KERNEL_CHOICES=(
    "linux"              "Stable kernel"
    "linux-lts"          "Long‑term support kernel"
    "linux-zen"          "Desktop responsiveness"
    "linux-hardened"     "Security‑focused kernel"
)

# --- Init systems ---
INIT_SYSTEMS=("openrc" "runit" "dinit" "s6")

# --- Filesystems ---
FS_TYPES=("ext4" "btrfs" "xfs" "f2fs" "exfat")

# --- Bootloaders ---
BOOTLOADERS=("grub" "refind" "efistub")

# --- Network stacks ---
NETWORK_STACKS=("networkmanager" "dhcpcd+iwd" "connman")

# --- Audio choices ---
AUDIO_CHOICES=(
    "pipewire"     "PipeWire (modern, recommended)"
    "pulseaudio"   "PulseAudio (legacy)"
    "none"         "No audio"
)

# --- Desktop environments (common selection) ---
DESKTOP_CHOICES=(
    "xfce4"    "XFCE desktop"
    "lxqt"     "LXQt desktop"
    "kde"      "KDE Plasma desktop"
    "i3wm"     "i3 window manager"
    "none"     "No desktop"
)

# --- Desktop package lists ---
declare -A DESKTOP_PACKAGES
DESKTOP_PACKAGES=(
    ["xfce4"]="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
    ["lxqt"]="lxqt sddm"
    ["kde"]="plasma-desktop dolphin konsole sddm"
    ["i3wm"]="i3-wm i3status i3lock dmenu xterm lightdm lightdm-gtk-greeter"
    ["none"]=""
)

# --- Display managers ---
DISPLAY_MANAGER_CHOICES=(
    "lightdm"  "LightDM"
    "sddm"     "SDDM"
    "none"     "None"
)

# --- Audio package lists ---
declare -A AUDIO_PACKAGES
AUDIO_PACKAGES=(
    ["pipewire"]="pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pavucontrol rtkit"
    ["pulseaudio"]="pulseaudio pulseaudio-alsa alsa-utils pavucontrol"
    ["none"]=""
)

# --- GPU drivers (common vendors) ---
declare -A GPU_PACKAGES
GPU_PACKAGES=(
    ["nvidia"]="nvidia-dkms nvidia-utils nvidia-settings mesa"
    ["intel"]="xf86-video-intel mesa vulkan-intel"
    ["amd"]="xf86-video-amdgpu mesa vulkan-radeon"
    ["vmware"]="open-vm-tools xf86-video-vmware"
    ["qemu"]="spice-vdagent qemu-guest-agent xf86-video-qxl"
    ["virtualbox"]="virtualbox-guest-utils"
    ["unknown"]="mesa xf86-video-vesa"
)

# --- Shells ---
SHELL_CHOICES=("bash" "zsh" "fish")

# --- Privilege escalation ---
PRIV_ESCALATION_CHOICES=("sudo" "doas" "none")

# --- Extras (small, common selection) ---
declare -A EXTRA_PACKAGES
EXTRA_PACKAGES=(
    ["firefox"]="firefox"
    ["neovim"]="neovim"
    ["alacritty"]="alacritty"
    ["mpv"]="mpv"
    ["flatpak"]="flatpak"
    ["firewalld"]="firewalld"
    ["git"]="git"
    ["htop"]="htop"
    ["tmux"]="tmux"
)

# --- Post-install hooks ---
artix_post_install() {
    log_info "Running Artix post‑install hooks..."
    pkg_chroot pacman-key --init
    pkg_chroot pacman-key --populate artix
}

# --- Network configuration ---
artix_setup_network() {
    local stack="${NETWORK_STACK:-networkmanager}" init="${INIT:-openrc}"
    case "${stack}" in
        networkmanager)
            pkg_install networkmanager "networkmanager-${init}"
            enable_service NetworkManager
            ;;
        dhcpcd+iwd)
            pkg_install dhcpcd iwd "dhcpcd-${init}" "iwd-${init}"
            enable_service dhcpcd
            enable_service iwd
            ;;
        connman)
            pkg_install connman "connman-${init}"
            enable_service connmand
            ;;
    esac
}