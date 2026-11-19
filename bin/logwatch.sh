#!/usr/bin/env bash
# logwatch.sh - summarise web access logs and SSH auth logs.
#
# Usage: logwatch.sh nginx  /var/log/nginx/access.log [TOP_N]
#        logwatch.sh auth   /var/log/auth.log [TOP_N]
# Exit:  1 if 5xx ratio > 5% (nginx) or failed SSH logins > threshold (auth)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

MODE="${1:-}"; FILE="${2:-}"; TOP="${3:-5}"
SSH_FAIL_THRESHOLD="${SSH_FAIL_THRESHOLD:-20}"
[[ -n "$MODE" && -r "$FILE" ]] || die "usage: logwatch.sh nginx|auth <logfile> [top_n]"

case "$MODE" in
  nginx)
    # combined log format: IP - - [time] "METHOD PATH PROTO" STATUS BYTES ...
    total=$(wc -l < "$FILE")
    (( total > 0 )) || { echo "empty log"; exit 0; }
    echo "== $FILE: $total requests =="
    echo "-- status classes --"
    awk '{print substr($9,1,1)"xx"}' "$FILE" | sort | uniq -c | sort -rn
    echo "-- top $TOP client IPs --"
    awk '{print $1}' "$FILE" | sort | uniq -c | sort -rn | head -n "$TOP"
    echo "-- top $TOP paths --"
    awk '{print $7}' "$FILE" | sort | uniq -c | sort -rn | head -n "$TOP"
    echo "-- top $TOP paths returning 5xx --"
    awk '$9 ~ /^5/ {print $7}' "$FILE" | sort | uniq -c | sort -rn | head -n "$TOP"
    errors=$(awk '$9 ~ /^5/' "$FILE" | wc -l)
    ratio=$(awk -v e="$errors" -v t="$total" 'BEGIN{printf "%.2f", e*100/t}')
    echo "5xx ratio: ${ratio}%"
    if awk -v r="$ratio" 'BEGIN{exit !(r > 5)}'; then
      send_alert "5xx ratio ${ratio}% in $FILE"; exit 1
    fi
    ;;
  auth)
    fails=$(grep -c 'Failed password' "$FILE" || true)
    echo "== $FILE =="
    echo "failed SSH password attempts : $fails"
    echo "accepted SSH logins          : $(grep -c 'Accepted ' "$FILE" || true)"
    echo "sudo commands                : $(grep -c 'sudo: .*COMMAND=' "$FILE" || true)"
    echo "-- top $TOP source IPs of failed logins --"
    grep 'Failed password' "$FILE" | grep -oE 'from [0-9.]+' | awk '{print $2}' \
      | sort | uniq -c | sort -rn | head -n "$TOP"
    echo "-- top $TOP targeted users --"
    grep 'Failed password' "$FILE" | sed -E 's/.*for (invalid user )?([^ ]+) from.*/\2/' \
      | sort | uniq -c | sort -rn | head -n "$TOP"
    if (( fails > SSH_FAIL_THRESHOLD )); then
      warn "possible brute force: $fails failed logins (threshold $SSH_FAIL_THRESHOLD)"
      send_alert "$fails failed SSH logins in $FILE"; exit 1
    fi
    ;;
  *) die "mode must be nginx or auth" ;;
esac
