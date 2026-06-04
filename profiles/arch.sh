#!/usr/bin/env bash
# Volk's Forge Framework – Arch Linux (generic reference profile)
# Source this after the framework core to configure for Arch.

# --- Package backend ---
CHROOT_CMD="arch-chroot"
PACMAN_KEYRING="archlinux"
PACMAN_BOOTSTRAP="pacstrap"
PACMAN_ARCH_SUPPORT="no"
source "${VFF_DIR}/lib/pkg/pacman.sh"

# --- Distro identity ---
DISTRO_NAME="Arch Linux"
DISTRO_ID="arch"
VFF_BOOTLOADER_ID="Arch"

# --- Hooks ---
VFF_NETWORK_HOOK="setup_arch_network"
VFF_FINALIZE_HOOK="arch_post_install"
VFF_REQUIRED_TOOLS="sgdisk partprobe mount lsblk wipefs"

# --- Base packages ---
BASE_PACKAGES=(
    base base-devel linux linux-firmware linux-headers
    bash vim nano sudo git curl wget
    pacman-contrib pciutils usbutils
    man-db man-pages
)

# --- Kernel choices ---
KERNEL_CHOICES=(
    "linux"              "Stable kernel"
    "linux-lts"          "Long‑term support kernel"
    "linux-zen"          "Desktop responsiveness"
    "linux-hardened"     "Security‑focused kernel"
)

# --- Init systems ---
INIT_SYSTEMS=("systemd")

# --- Filesystems ---
FS_TYPES=("ext4" "btrfs" "xfs" "f2fs" "exfat")

# --- Bootloaders ---
BOOTLOADERS=("grub" "systemd-boot" "efistub")

# --- Network stacks ---
NETWORK_STACKS=("networkmanager" "dhcpcd+iwd")

# --- Audio choices ---
AUDIO_CHOICES=(
    "pipewire"     "PipeWire (modern, recommended)"
    "pulseaudio"   "PulseAudio (legacy)"
    "none"         "No audio"
)

# --- Desktop environments (common selection) ---
DESKTOP_CHOICES=(
    "gnome"   "GNOME desktop"
    "kde"     "KDE Plasma desktop"
    "xfce"    "XFCE desktop"
    "i3"      "i3 window manager"
    "none"    "No desktop"
)

# --- Desktop package lists ---
declare -A DESKTOP_PACKAGES
DESKTOP_PACKAGES=(
    ["gnome"]="gnome gnome-tweaks gdm"
    ["kde"]="plasma-desktop dolphin konsole sddm"
    ["xfce"]="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
    ["i3"]="i3-wm i3status i3lock dmenu xterm lightdm lightdm-gtk-greeter"
    ["none"]=""
)

# --- Display managers ---
DISPLAY_MANAGER_CHOICES=(
    "gdm"      "GDM"
    "sddm"     "SDDM"
    "lightdm"  "LightDM"
    "none"     "None"
)

# --- Audio package lists ---
declare -A AUDIO_PACKAGES
AUDIO_PACKAGES=(
    ["pipewire"]="pipewire pipewire-pulse pipewire-alsa wireplumber"
    ["pulseaudio"]="pulseaudio pulseaudio-alsa"
    ["none"]=""
)

# --- GPU drivers (common vendors) ---
declare -A GPU_PACKAGES
GPU_PACKAGES=(
    ["nvidia"]="nvidia-dkms nvidia-utils nvidia-settings"
    ["intel"]="xf86-video-intel mesa vulkan-intel"
    ["amd"]="xf86-video-amdgpu mesa vulkan-radeon"
    ["vmware"]="open-vm-tools xf86-video-vmware"
    ["qemu"]="spice-vdagent qemu-guest-agent xf86-video-qxl"
    ["virtualbox"]="virtualbox-guest-utils"
    ["unknown"]="mesa xf86-video-vesa"
)

# --- Shells ---
SHELL_CHOICES=(
    "bash"  "Bash"
    "zsh"   "Zsh"
    "fish"  "Fish"
)

# --- Privilege escalation ---
PRIV_ESCALATION_CHOICES=(
    "sudo"  "sudo"
    "doas"  "doas"
    "none"  "None"
)

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
arch_post_install() {
    log_info "Running Arch post‑install hooks..."
    pkg_chroot systemd-machine-id-setup
    pkg_chroot pacman-key --init
    pkg_chroot pacman-key --populate archlinux
}

# --- Network configuration ---
setup_arch_network() {
    local stack="${NETWORK_STACK:-networkmanager}"
    case "${stack}" in
        networkmanager)
            pkg_install networkmanager
            systemctl enable NetworkManager
            ;;
        dhcpcd+iwd)
            pkg_install dhcpcd iwd
            systemctl enable dhcpcd
            systemctl enable iwd
            ;;
    esac
}