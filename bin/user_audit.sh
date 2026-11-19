#!/usr/bin/env bash
# user_audit.sh - security audit of local accounts.
#
# Usage: user_audit.sh [--passwd FILE] [--group FILE]
#   (file overrides exist so the script can be tested against fixtures)
# Reports: login-capable users, UID 0 accounts, sudo/wheel members,
#          accounts with empty password hashes (needs root for /etc/shadow).
# Exit:  1 if a risky finding exists (extra UID 0 or empty password)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

PASSWD=/etc/passwd; GROUP=/etc/group; SHADOW=/etc/shadow
while (( $# )); do
  case "$1" in
    --passwd) PASSWD="$2"; shift ;; --group) GROUP="$2"; shift ;; --shadow) SHADOW="$2"; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
risk=0

echo "-- users with a login shell --"
awk -F: '$7 !~ /(nologin|false|sync|halt|shutdown)$/ {printf "  %-15s uid=%-6s home=%s shell=%s\n", $1, $3, $6, $7}' "$PASSWD"

echo "-- UID 0 accounts --"
uid0=$(awk -F: '$3 == 0 {print $1}' "$PASSWD")
echo "$uid0" | sed 's/^/  /'
if [[ "$(echo "$uid0" | grep -vc '^root$')" -gt 0 ]]; then
  warn "non-root account(s) with UID 0 found"; risk=1
fi

echo "-- sudo / wheel / admin group members --"
awk -F: '$1 ~ /^(sudo|wheel|admin)$/ {print "  " $1 ": " ($4 == "" ? "(none)" : $4)}' "$GROUP"

echo "-- empty password hashes --"
if [[ -r "$SHADOW" ]]; then
  empty=$(awk -F: '$2 == "" {print $1}' "$SHADOW")
  if [[ -n "$empty" ]]; then echo "$empty" | sed 's/^/  /'; warn "accounts with empty passwords"; risk=1
  else echo "  none"; fi
else
  echo "  (skipped: $SHADOW not readable, run as root)"
fi
exit "$risk"
