# playful-archers-build

My favorite Arch Linux apps, with a script to install them all and a script to configure them.

## New machine, the Omarchy way

1. Install [Omarchy](https://omarchy.org).
2. Add Plasma with [omarchy-plasma](https://github.com/paulcfry67/omarchy-plasma):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/paulcfry67/omarchy-plasma/main/install.sh | bash
   ```
3. Reboot, then run this repo:
   ```bash
   git clone https://github.com/paulcfry67/playful-archers-build.git
   cd playful-archers-build
   ./install.sh --server --nvidia     # pick the flags that fit the machine
   ```

4. Configure:
   ```bash
   ./configure.sh
   ```

## What configure.sh does

| Step | Change |
|---|---|
| vi → vim | Symlinks `/usr/local/bin/vi` to vim, so `vi` works everywhere, including under sudo and in scripts |
| Services | Enables NetworkManager, Bluetooth, CUPS, Tailscale, cron, `at`, weekly SSD trim and package-cache cleanup, Syncthing for your user, and Docker, libvirt and xrdp when `--server` installed them |
| Groups | Adds you to the `docker` and `libvirt` groups when they exist |
| Nightly update | A systemd timer downloads updates at 02:00, so installing them yourself (`sudo pacman -Syu` or `omarchy update`) takes seconds. With `--full-update` it installs them too, after a snapper snapshot when snapper is set up. If the machine was off, it runs soon after the next boot. AUR packages are left for `yay -Sua` |

Options: `--update-time HH:MM`, `--full-update` (install updates at night too, decided machine by machine), `--no-auto-update`, `--dry-run`.

To switch a machine between modes later, just re-run `./configure.sh` with or without `--full-update`.

Check on it with `systemctl list-timers playful-auto-update.timer` and `journalctl -u playful-auto-update`.

## Plain Arch machines

| Machine | Command |
|---|---|
| PHILLIPS (AMD, Plasma) | `./install.sh --plasma --amd --epson` |
| LEONA (Nvidia, server roles) | `./install.sh --plasma --nvidia --server` |

## Options

| Flag | Adds |
|---|---|
| `--server` | `server.txt`: Docker, Jenkins, QEMU/libvirt VMs, xrdp, restic backup server, ntfy, system mail |
| `--plasma` | `desktop-plasma.txt`: full KDE Plasma (plain Arch only; ignored on Omarchy) |
| `--amd` | `hw-amd.txt`: Radeon drivers, sound firmware |
| `--nvidia` | `hw-nvidia.txt`: Nvidia settings, CUDA, cuDNN, Ollama, ONNX Runtime. On plain Arch also `hw-nvidia-driver.txt` (the driver itself); on Omarchy the driver comes from Omarchy |
| `--epson` | `hw-epson.txt`: Epson inkjet driver |
| `--dry-run` | Prints the commands without running them |

`apps.txt` and `dev.txt` are always installed.

## Package lists

All lists live in `packages/`. One package per line, and `#` starts a comment. The script asks pacman whether each package is in the official repos and sends the rest to yay, so official and AUR packages can sit side by side; `# AUR` comments are just notes.

Lines marked `# also in Omarchy` are already installed by Omarchy. They stay so the script also works on plain Arch; `--needed` skips them on Omarchy.

## Left out on purpose

- **Base system:** `base`, `linux`, `linux-firmware`, `efibootmgr`, `lvm2`, CPU microcode. The Arch or Omarchy installer sets these up.
- **Login managers:** `sddm`, `plasma-login-manager`. Omarchy brings sddm and omarchy-plasma configures it.
- **Hyprland setup:** `hyprland`, `waybar`, `wofi`, `mako`, `dunst`, `grim`, `slurp` and friends. Omarchy brings its own.
- **KDE's full app collection** (games, education, KDE email and calendar suite).
- **Unused for most of 2026 on LEONA:** `lima`, `most`, `pass`, `postgrey`, `viewnior`, `lsd`, `tree`, `bridge-utils`, `virt-viewer`, `wireless_tools`, `nvidia-prime`, and the `twm`/`xclock`/`xterm` test session.
- `iwd` (Omarchy turns it off in favor of NetworkManager) and debug-symbol packages (`*-debug`).
