#!/usr/bin/env bash
# playful-archers-build — configure the apps installed by install.sh.
#
# Usage: ./configure.sh [options]
#   --update-time HH:MM   Time of the nightly system update (default 02:00)
#   --full-update         Nightly job installs updates too (default: download only)
#   --no-auto-update      Don't set up the nightly update
#   --dry-run             Show what would be done without changing anything
#
# Safe to run more than once: every step checks before it changes anything.
set -euo pipefail

UPDATE_TIME="02:00"; UPDATE_MODE="download"; AUTO_UPDATE=1; DRY=0

while (( $# )); do
  case "$1" in
    --update-time)    [[ $# -ge 2 && $2 =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || { echo "--update-time needs HH:MM" >&2; exit 1; }
                      UPDATE_TIME="$2"; shift ;;
    --full-update)    UPDATE_MODE="full" ;;
    --no-auto-update) AUTO_UPDATE=0 ;;
    --dry-run)        DRY=1 ;;
    -h|--help)        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

(( EUID != 0 )) || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
run()  { if (( DRY )); then echo "  + $*"; else "$@"; fi; }

# Write stdin to a root-owned file, only if its content changed.
write_root_file() {
  local dest="$1" mode="$2" content
  content="$(cat)"
  if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$content" ]]; then
    ok "$dest already up to date"; return
  fi
  if (( DRY )); then
    echo "  + write $dest:"; printf '%s\n' "$content" | sed 's/^/      /'
  else
    printf '%s\n' "$content" | sudo install -D -m "$mode" /dev/stdin "$dest"
    ok "Wrote $dest"
  fi
}

unit_exists() { systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .; }

(( DRY )) || sudo true

# ---------- 1. vi runs vim ----------
step "vi → vim"
# A symlink rather than an alias, so it also works under sudo, in scripts and for git.
if [[ "$(readlink /usr/local/bin/vi 2>/dev/null)" == /usr/bin/vim ]]; then
  ok "vi already points to vim"
elif [[ -x /usr/bin/vim ]] || (( DRY )); then
  run sudo ln -sf /usr/bin/vim /usr/local/bin/vi
  ok "vi now runs vim (/usr/local/bin/vi)"
else
  echo "  ! vim not installed; run install.sh first"
fi

# ---------- 2. services ----------
step "Services"
# Only units that exist are touched, so --server packages are covered when installed.
SERVICES=(
  NetworkManager.service   # networking
  bluetooth.service        # Bluetooth
  cups.socket              # printing, started on demand
  tailscaled.service       # Tailscale VPN
  cronie.service           # cron jobs
  atd.service              # one-off `at` jobs
  fstrim.timer             # weekly SSD trim
  paccache.timer           # weekly package-cache cleanup (keeps 3 versions)
  docker.service           # --server
  libvirtd.service         # --server
  xrdp.service             # --server
)
for unit in "${SERVICES[@]}"; do
  if ! unit_exists "$unit"; then continue; fi
  if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
    ok "$unit already enabled"
  else
    run sudo systemctl enable --now "$unit"
    ok "Enabled $unit"
  fi
done

# Syncthing runs as your user, not as root.
if command -v syncthing >/dev/null; then
  if systemctl --user is-enabled --quiet syncthing.service 2>/dev/null; then
    ok "syncthing (user) already enabled"
  else
    run systemctl --user enable --now syncthing.service
    ok "Enabled syncthing for $USER"
  fi
fi

# ---------- 3. groups ----------
step "Groups"
for g in docker libvirt; do
  getent group "$g" >/dev/null || continue
  if id -nG "$USER" | tr ' ' '\n' | grep -qx "$g"; then
    ok "$USER already in $g"
  else
    run sudo usermod -aG "$g" "$USER"
    ok "Added $USER to $g (takes effect at next login)"
  fi
done

# ---------- 4. nightly update ----------
step "Nightly system update"
if (( ! AUTO_UPDATE )); then
  echo "  Skipped (--no-auto-update)"
else
  write_root_file /usr/local/sbin/playful-auto-update 0755 <<'EOF'
#!/usr/bin/env bash
# Nightly update, run by playful-auto-update.timer. Installed by playful-archers-build.
# Log: journalctl -u playful-auto-update
set -uo pipefail
mode="${1:-full}"

if [[ $mode == download ]]; then
  echo "Downloading updates only"
  exec pacman -Syuw --noconfirm
fi

# Snapshot first when snapper is set up (Omarchy sets it up for /).
if command -v snapper >/dev/null && snapper list-configs 2>/dev/null | grep -qE '^root[[:space:]]'; then
  snapper -c root create -c number -d "before nightly update" \
    && echo "Snapshot created" || echo "Snapshot failed; continuing without one"
fi

pacman -Syu --noconfirm
status=$?
if (( status == 0 )); then
  echo "Update finished"
else
  echo "Update FAILED (exit $status); run 'sudo pacman -Syu' by hand to see why"
fi
exit "$status"
EOF

  write_root_file /etc/systemd/system/playful-auto-update.service 0644 <<EOF
[Unit]
Description=Nightly system update (playful-archers-build)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/playful-auto-update $UPDATE_MODE
Nice=10
IOSchedulingClass=idle
EOF

  write_root_file /etc/systemd/system/playful-auto-update.timer 0644 <<EOF
[Unit]
Description=Run the nightly system update at $UPDATE_TIME

[Timer]
OnCalendar=*-*-* $UPDATE_TIME:00
# If the machine was off at $UPDATE_TIME, run soon after the next boot.
Persistent=true

[Install]
WantedBy=timers.target
EOF

  run sudo systemctl daemon-reload
  run sudo systemctl enable --now playful-auto-update.timer
  if [[ $UPDATE_MODE == full ]]; then
    ok "Nightly update scheduled for $UPDATE_TIME: downloads and installs"
  else
    ok "Nightly update scheduled for $UPDATE_TIME: downloads only; install with 'sudo pacman -Syu'"
    echo "    Re-run with --full-update to have it install updates too."
  fi
fi

step "Done"
cat <<EOF
  Check the nightly update:  systemctl list-timers playful-auto-update.timer
  Read its last run:         journalctl -u playful-auto-update -n 50
  AUR packages aren't included in the nightly run; update them with: yay -Sua
EOF
