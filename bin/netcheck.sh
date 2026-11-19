#!/usr/bin/env bash
# netcheck.sh - check DNS, TCP and HTTP reachability for a list of targets.
#
# Usage: netcheck.sh [-f targets.txt] [target ...]
#   target formats:  dns:example.com   tcp:10.0.0.5:22   http:https://example.com/health
# Exit:  number of failed checks (0 = all passed, capped at 125)
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

TIMEOUT="${NETCHECK_TIMEOUT:-3}"
targets=()
while (( $# )); do
  case "$1" in
    -f) mapfile -t -O "${#targets[@]}" targets < <(grep -Ev '^\s*(#|$)' "$2"); shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) targets+=("$1") ;;
  esac
  shift
done
(( ${#targets[@]} )) || die "no targets given (see --help)"

fails=0
result() {  # status type target detail
  local color=$C_GRN; [[ "$1" == FAIL ]] && { color=$C_RED; ((fails++)); }
  printf '%s%-4s%s  %-5s %-40s %s\n' "$color" "$1" "$C_RST" "$2" "$3" "$4"
}

check_dns() {
  local ips
  if ips=$(getent ahosts "$1" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd' ' -) && [[ -n "$ips" ]]; then
    result OK dns "$1" "$ips"
  else
    result FAIL dns "$1" "does not resolve"
  fi
}

check_tcp() {
  local host=${1%:*} port=${1##*:} start end
  start=$(date +%s%N)
  if timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    end=$(date +%s%N)
    result OK tcp "$1" "connected in $(( (end - start) / 1000000 ))ms"
  else
    result FAIL tcp "$1" "closed/filtered or timeout (${TIMEOUT}s)"
  fi
}

check_http() {
  local out code t
  if out=$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' --max-time "$TIMEOUT" "$1" 2>&1); then
    read -r code t <<< "$out"
    if [[ "$code" =~ ^[23] ]]; then result OK http "$1" "HTTP $code in ${t}s"
    else result FAIL http "$1" "HTTP $code"; fi
  else
    result FAIL http "$1" "${out##*: }"
  fi
}

for t in "${targets[@]}"; do
  case "$t" in
    dns:*)  check_dns  "${t#dns:}" ;;
    tcp:*)  check_tcp  "${t#tcp:}" ;;
    http:*) check_http "${t#http:}" ;;
    *) result FAIL "?" "$t" "unknown target type (use dns:, tcp:, http:)" ;;
  esac
done

echo "---"; echo "${#targets[@]} checks, $fails failed"
exit $(( fails > 125 ? 125 : fails ))
