#!/usr/bin/env bash
# Shared helpers sourced by every script in bin/.
# shellcheck disable=SC2034  # colour vars are used by callers

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_DIM=""; C_RST=""
fi

_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log()  { printf '%s %s[INFO]%s %s\n'  "$(_ts)" "$C_GRN" "$C_RST" "$*" >&2; }
warn() { printf '%s %s[WARN]%s %s\n'  "$(_ts)" "$C_YLW" "$C_RST" "$*" >&2; }
err()  { printf '%s %s[ERROR]%s %s\n' "$(_ts)" "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# require_cmd curl tar ... -> exits if any command is missing
require_cmd() {
  local missing=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  (( ${#missing[@]} == 0 )) || die "missing required command(s): ${missing[*]}"
}

# send_alert "message" -> posts to $ALERT_WEBHOOK_URL (Slack/Teams/any JSON webhook) if set
send_alert() {
  local msg="$1"
  [[ -n "${ALERT_WEBHOOK_URL:-}" ]] || return 0
  curl -fsS --max-time 5 -H 'Content-Type: application/json' \
    -d "{\"text\": \"[$(hostname)] ${msg//\"/\\\"}\"}" "$ALERT_WEBHOOK_URL" >/dev/null \
    || warn "failed to deliver alert to webhook"
}

# human_bytes 1536 -> 1.5K
human_bytes() {
  awk -v b="$1" 'BEGIN { s="BKMGTP"; i=1; while (b >= 1024 && i < 6) { b /= 1024; i++ } ;
    if (i == 1) printf "%dB\n", b; else printf "%.1f%s\n", b, substr(s, i, 1) }'
}
