#!/usr/bin/env bash
# sysreport.sh - one-shot Linux health report (text or JSON).
#
# Usage: sysreport.sh [--json] [--disk-warn PCT] [--mem-warn PCT]
# Exit:  0 healthy, 1 warnings found, 2 usage error
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib/common.sh"

JSON=0; DISK_WARN=85; MEM_WARN=90
while (( $# )); do
  case "$1" in
    --json) JSON=1 ;;
    --disk-warn) DISK_WARN="$2"; shift ;;
    --mem-warn)  MEM_WARN="$2"; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

warnings=()

# --- CPU / load ---
read -r load1 load5 load15 _ < /proc/loadavg
cores=$(nproc)
if awk -v l="$load5" -v c="$cores" 'BEGIN{exit !(l > c)}'; then
  warnings+=("load5 $load5 exceeds $cores cores")
fi

# --- Memory (from /proc/meminfo, in kB) ---
mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
mem_used_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
(( mem_used_pct >= MEM_WARN )) && warnings+=("memory ${mem_used_pct}% used")

# --- Disks ---
disk_lines=()
while read -r mnt pct; do
  p=${pct%\%}
  disk_lines+=("$mnt $p")
  (( p >= DISK_WARN )) && warnings+=("disk $mnt at ${p}%")
done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | awk 'NR>1 {print $6, $5}')

# --- Listening ports ---
ports=""
command -v ss >/dev/null && ports=$(ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | sort -nu | paste -sd, -)

# --- Failed systemd units ---
failed_units=""
if command -v systemctl >/dev/null && systemctl is-system-running >/dev/null 2>&1; then
  failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd, -)
  [[ -n "$failed_units" ]] && warnings+=("failed units: $failed_units")
fi

# --- Top processes by memory ---
top_procs=$(ps -eo pid,comm,%mem,%cpu --sort=-%mem 2>/dev/null | head -6)

if (( JSON )); then
  python3 - "$load1" "$load5" "$load15" "$cores" "$mem_used_pct" "$ports" "$failed_units" \
           "$(printf '%s\n' "${disk_lines[@]}")" "$(printf '%s\n' "${warnings[@]}")" <<'PY'
import json, socket, sys
l1, l5, l15, cores, mem, ports, failed, disks, warns = sys.argv[1:]
print(json.dumps({
    "host": socket.gethostname(),
    "load": {"1m": float(l1), "5m": float(l5), "15m": float(l15), "cores": int(cores)},
    "memory_used_pct": int(mem),
    "disks": [{"mount": d.split()[0], "used_pct": int(d.split()[1])} for d in disks.splitlines() if d],
    "listening_ports": [int(p) for p in ports.split(",") if p],
    "failed_units": [u for u in failed.split(",") if u],
    "warnings": [w for w in warns.splitlines() if w],
    "status": "warn" if warns.strip() else "ok",
}, indent=2))
PY
else
  echo "=== System report: $(hostname) @ $(date) ==="
  echo "Kernel   : $(uname -sr)"
  echo "Uptime   : $(uptime -p 2>/dev/null || echo "$(cut -d' ' -f1 /proc/uptime)s")"
  echo "Load     : $load1 $load5 $load15 (cores: $cores)"
  echo "Memory   : ${mem_used_pct}% used of $(human_bytes $((mem_total * 1024)))"
  echo "Disks    :"; for d in "${disk_lines[@]}"; do read -r m u <<< "$d"; printf '  %-25s %3s%%\n' "$m" "$u"; done
  echo "Ports    : ${ports:-n/a}"
  echo "Failed   : ${failed_units:-none}"
  echo "Top memory processes:"; echo "$top_procs" | sed 's/^/  /'
  echo
  if (( ${#warnings[@]} )); then
    echo "${C_YLW}WARNINGS:${C_RST}"; printf '  - %s\n' "${warnings[@]}"
  else
    echo "${C_GRN}All checks OK${C_RST}"
  fi
fi

(( ${#warnings[@]} == 0 ))
