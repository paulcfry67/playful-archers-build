#!/usr/bin/env bash
# playful-archers-build — install Paul's favorite apps.
#
# Intended order on a new machine:
#   1. Install Omarchy
#   2. Run omarchy-plasma  (https://github.com/paulcfry67/omarchy-plasma)
#   3. Run this script
#
# Usage: ./install.sh [--server] [--plasma] [--amd] [--nvidia] [--epson] [--dry-run]
#   --server   Also install server roles: Docker, Jenkins, VMs, xrdp, backup server
#   --plasma   Also install KDE Plasma (plain Arch only; on Omarchy use omarchy-plasma)
#   --amd      Also install AMD Radeon drivers and sound firmware
#   --nvidia   Also install Nvidia settings, CUDA and GPU AI tools (plus the driver on plain Arch)
#   --epson    Also install the Epson inkjet printer driver
#   --dry-run  Show the commands without running them
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$DIR/packages"
SERVER=0; PLASMA=0; AMD=0; NVIDIA=0; EPSON=0; DRY=0

for arg in "$@"; do
  case "$arg" in
    --server)  SERVER=1 ;;
    --plasma)  PLASMA=1 ;;
    --amd)     AMD=1 ;;
    --nvidia)  NVIDIA=1 ;;
    --epson)   EPSON=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

(( EUID != 0 )) || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

# Read a list file: strip comments, trailing spaces and blank lines.
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"; }
run() { if (( DRY )); then echo "  + $*"; else "$@"; fi; }

# ---------- preflight ----------
OMARCHY=0
[[ -d "$HOME/.local/share/omarchy" || -d /usr/share/omarchy ]] && OMARCHY=1

if (( OMARCHY )); then
  echo "==> Omarchy detected"
  if (( PLASMA )); then
    echo "  ! --plasma ignored on Omarchy: omarchy-plasma handles the Plasma install." >&2
    PLASMA=0
  fi
  if [[ ! -f /usr/share/wayland-sessions/plasma.desktop ]]; then
    echo "  ! Plasma isn't installed yet. Run omarchy-plasma first, then re-run this script." >&2
    (( DRY )) || exit 1
  fi
fi

# ---------- choose lists ----------
lists=("$PKG/apps.txt" "$PKG/dev.txt")
(( SERVER )) && lists+=("$PKG/server.txt")
(( PLASMA )) && lists+=("$PKG/desktop-plasma.txt")
(( AMD ))    && lists+=("$PKG/hw-amd.txt")
(( EPSON ))  && lists+=("$PKG/hw-epson.txt")
if (( NVIDIA )); then
  lists+=("$PKG/hw-nvidia.txt")
  (( OMARCHY )) || lists+=("$PKG/hw-nvidia-driver.txt")
fi

echo "==> Updating system"
run sudo pacman -Syu --noconfirm

# Sort every package into official repo or AUR by asking pacman's sync database.
repo=(); aur=()
while read -r p; do
  if pacman -Si "$p" &>/dev/null; then repo+=("$p"); else aur+=("$p"); fi
done < <(for f in "${lists[@]}"; do read_list "$f"; done | awk '!seen[$0]++')

# ---------- repo packages ----------
echo "==> Installing ${#repo[@]} repo packages (already-installed ones are skipped)"
run sudo pacman -S --needed --noconfirm "${repo[@]}"

# ---------- AUR packages ----------
if (( ${#aur[@]} )); then
  if ! command -v yay >/dev/null; then
    echo "==> Bootstrapping yay"
    tmp="$(mktemp -d)"
    run git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    if (( ! DRY )); then (cd "$tmp/yay" && makepkg -si --noconfirm); fi
    rm -rf "$tmp"
  fi
  echo "==> Installing ${#aur[@]} AUR packages: ${aur[*]}"
  run yay -S --needed --noconfirm "${aur[@]}"
fi

echo "==> Done. Next: run ./configure.sh to enable services and apply settings."
