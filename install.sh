#!/usr/bin/env bash
# Install the toolkit to /opt/ops-toolkit and symlink commands into /usr/local/bin.
#   sudo ./install.sh            install
#   sudo ./install.sh --timers   install + enable systemd timers
#   sudo ./install.sh --uninstall
set -Eeuo pipefail
PREFIX="${PREFIX:-/opt/ops-toolkit}"
BINDIR="${BINDIR:-/usr/local/bin}"
SRC="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  for f in "$SRC"/bin/*.sh; do rm -f "$BINDIR/$(basename "$f" .sh)"; done
  systemctl disable --now ops-sysreport.timer ops-backup.timer 2>/dev/null || true
  rm -f /etc/systemd/system/ops-*.{service,timer}
  rm -rf "$PREFIX"
  echo "uninstalled"; exit 0
fi

install -d "$PREFIX"/{bin,lib} /var/log/ops-toolkit
install -m 0755 "$SRC"/bin/*.sh "$PREFIX/bin/"
install -m 0644 "$SRC"/lib/*.sh "$PREFIX/lib/"
for f in "$PREFIX"/bin/*.sh; do ln -sf "$f" "$BINDIR/$(basename "$f" .sh)"; done
[[ -f /etc/default/ops-toolkit ]] || install -m 0640 "$SRC/systemd/ops-toolkit.env" /etc/default/ops-toolkit
cmds=(); for f in "$SRC"/bin/*.sh; do cmds+=("$(basename "$f" .sh)"); done
echo "installed to $PREFIX; commands: ${cmds[*]}"

if [[ "${1:-}" == "--timers" ]]; then
  install -m 0644 "$SRC"/systemd/ops-*.{service,timer} /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now ops-sysreport.timer ops-backup.timer
  systemctl list-timers 'ops-*'
fi
