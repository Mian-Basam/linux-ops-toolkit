#!/usr/bin/env bash
# service_watchdog.sh - keep a service healthy; restart it and alert if not.
#
# Usage: service_watchdog.sh -n NAME [-u HEALTH_URL] [-r "RESTART_CMD"] [-m MAX_RESTARTS]
#   NAME          systemd unit, or process name if systemd is not available
#   HEALTH_URL    optional HTTP endpoint that must return 2xx
#   RESTART_CMD   default: systemctl restart NAME
#   MAX_RESTARTS  per hour before giving up and alerting (default 3)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

NAME=""; URL=""; RESTART=""; MAX=3
STATE_DIR="${STATE_DIR:-/tmp/watchdog}"
while (( $# )); do
  case "$1" in
    -n) NAME="$2"; shift ;; -u) URL="$2"; shift ;;
    -r) RESTART="$2"; shift ;; -m) MAX="$2"; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
[[ -n "$NAME" ]] || die "-n NAME is required"
RESTART="${RESTART:-systemctl restart $NAME}"
mkdir -p "$STATE_DIR"; history="$STATE_DIR/$NAME.restarts"

is_running() {
  if command -v systemctl >/dev/null && systemctl list-unit-files "$NAME.service" >/dev/null 2>&1 \
     && systemctl is-system-running >/dev/null 2>&1; then
    systemctl is-active --quiet "$NAME"
  else
    pgrep -x "$NAME" >/dev/null
  fi
}
is_healthy() { [[ -z "$URL" ]] || curl -fsS --max-time 3 -o /dev/null "$URL"; }

if is_running && is_healthy; then
  log "$NAME healthy"; exit 0
fi

# rate-limit restarts: count entries in the last hour
now=$(date +%s)
recent=$(awk -v n="$now" '$1 > n-3600' "$history" 2>/dev/null | wc -l)
if (( recent >= MAX )); then
  err "$NAME unhealthy and already restarted $recent times in the last hour - giving up"
  send_alert "$NAME is DOWN; restart limit ($MAX/h) reached, manual action needed"
  exit 2
fi

warn "$NAME unhealthy - restarting (attempt $((recent + 1))/$MAX this hour)"
echo "$now" >> "$history"
if bash -c "$RESTART"; then
  sleep "${WATCHDOG_SETTLE:-3}"
  if is_running && is_healthy; then
    log "$NAME recovered after restart"; send_alert "$NAME was down and has been restarted"; exit 0
  fi
fi
err "$NAME still unhealthy after restart"; send_alert "$NAME restart FAILED"; exit 1
