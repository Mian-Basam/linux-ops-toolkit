#!/usr/bin/env bash
# Linux Ops Toolkit - one entry point for every common task.
#
#   ./run.sh                 show help
#   ./run.sh doctor          check that the required tools are installed
#   ./run.sh demo            run sysreport + netcheck from the repo (no install)
#   ./run.sh check           lint (shellcheck) + tests (bats)
#
# Run "./run.sh help" for the full list.
set -euo pipefail
cd "$(dirname "$0")"

# Use tools installed by ../install.sh (shared ../.venv and ~/.local/bin); nothing to activate.
[[ -x ../.venv/bin/python ]] && PATH="$(cd .. && pwd)/.venv/bin:$PATH"
PATH="$HOME/.local/bin:$PATH"; export PATH

c_ok=$'\e[32m'; c_err=$'\e[31m'; c_dim=$'\e[2m'; c_off=$'\e[0m'
[[ -t 1 && -z "${NO_COLOR:-}" ]] || { c_ok=""; c_err=""; c_dim=""; c_off=""; }
say()  { printf '%s>>%s %s\n' "$c_ok" "$c_off" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$c_err" "$c_off" "$*" >&2; exit 1; }
need() { local m=(); for t in "$@"; do command -v "$t" >/dev/null || m+=("$t"); done
         ((${#m[@]} == 0)) || die "missing tool(s): ${m[*]}  (fix: ./run.sh install-deps)"; }
linux_only() { [[ "$(uname -s)" == "Linux" ]] || die "'$1' needs Linux (systemd, /proc, ss). On macOS/Windows use: ./run.sh test-linux | demo-linux"; }
# Run "./run.sh <args>" inside a throwaway Ubuntu container (for macOS / Windows hosts).
in_linux() {
  command -v docker >/dev/null || die "Docker is needed to run Linux commands on $(uname -s) (../install.sh 01)"
  docker info >/dev/null 2>&1 || die "Docker is not running - start Docker Desktop first"
  say "running './run.sh $*' inside an Ubuntu 24.04 container"
  docker run --rm -t -v "$PWD":/work -w /work ubuntu:24.04 bash -c \
    "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq shellcheck bats python3 iproute2 procps curl ca-certificates make >/dev/null && ./run.sh $*"
}

doctor() {
  local rc=0
  printf 'OS: %s\n\n' "$(uname -s)"
  [[ "$(uname -s)" == "Linux" ]] || printf '%sNote:%s the scripts target Linux. On this machine use ./run.sh test-linux and ./run.sh demo-linux (needs Docker).\n\n' "$c_err" "$c_off"
  for t in bash awk tar sha256sum curl getent ss systemctl shellcheck bats; do
    if command -v "$t" >/dev/null; then printf '  %sok%s       %s\n' "$c_ok" "$c_off" "$t"
    else printf '  %smissing%s  %s\n' "$c_err" "$c_off" "$t"; rc=1; fi
  done
  printf '\n%sInstall everything automatically: ./run.sh install-deps   (or ../install.sh 01)%s\n' "$c_dim" "$c_off"
  return $rc
}

usage() {
  cat <<EOF
Linux Ops Toolkit - run.sh

Usage: ./run.sh <command> [args]

Setup
  install-deps         install every dependency for this project (../install.sh 01)
  doctor               check required tools are installed
  install              install to /opt/ops-toolkit (sudo, Linux)
  install-timers       install + enable systemd timers (sudo, Linux)
  uninstall            remove the toolkit and timers (sudo, Linux)

Quality
  lint                 shellcheck every script
  test                 run the Bats test suite
  check                lint + test
  test-linux           lint + test inside an Ubuntu Docker container (works on macOS)
  demo-linux           run the demo inside an Ubuntu Docker container (works on macOS)

Use the tools (straight from the repo, no install needed)
  demo                 sysreport + a sample netcheck
  sysreport [--json]   system health report
  netcheck <targets>   e.g. dns:github.com tcp:github.com:443 http:https://github.com
  backup <args>        e.g. -s /etc -d /tmp/backups -k 7
  logwatch <args>      e.g. auth tests/fixtures/auth.log
  watchdog <args>      e.g. -n nginx -u http://localhost/ -m 3
  audit                user/security audit (sudo for full results)
EOF
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  help|-h|--help) usage ;;
  install-deps)
    [[ -x ../install.sh ]] || die "../install.sh not found: it is in the full portfolio repo (git clone https://github.com/Mian-Basam/devops-portfolio)"
    exec ../install.sh 01 "$@" ;;
  doctor)         doctor ;;
  lint)           need shellcheck; say "shellcheck"; shellcheck bin/*.sh lib/*.sh install.sh run.sh && say "lint passed" ;;
  test)           need bats; say "bats tests/"; bats tests/ ;;
  check)          "$0" lint && "$0" test ;;
  test-linux)     in_linux check ;;
  demo-linux)     in_linux demo ;;
  install)        linux_only install;        sudo ./install.sh ;;
  install-timers) linux_only install-timers; sudo ./install.sh --timers ;;
  uninstall)      linux_only uninstall;      sudo ./install.sh --uninstall ;;
  demo)
    linux_only demo
    say "sysreport";  ./bin/sysreport.sh || true
    echo
    say "netcheck";   ./bin/netcheck.sh dns:github.com tcp:github.com:443 http:https://github.com || true
    echo
    say "logwatch (fixture SSH auth log)"; ./bin/logwatch.sh auth tests/fixtures/auth.log || true ;;
  sysreport)      ./bin/sysreport.sh "$@" ;;
  netcheck)       ./bin/netcheck.sh "$@" ;;
  backup)         ./bin/backup.sh "$@" ;;
  logwatch)       ./bin/logwatch.sh "$@" ;;
  watchdog)       ./bin/service_watchdog.sh "$@" ;;
  audit)          ./bin/user_audit.sh "$@" ;;
  *)              usage; die "unknown command: $cmd" ;;
esac
