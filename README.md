# Linux Ops Toolkit

[![CI](https://github.com/Mian-Basam/linux-ops-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/Mian-Basam/linux-ops-toolkit/actions)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnubash&logoColor=white)
![Tests](https://img.shields.io/badge/tests-18%20passing-brightgreen)
![Level](https://img.shields.io/badge/level-basic-blue)

> Production-style **Bash** commands for everyday Linux server
> administration, scheduled with **systemd timers**, linted with
> **ShellCheck** and tested with **Bats**.
>
> **Portfolio level 1 of 5**: the Linux and scripting foundation that the other projects build on.

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Purpose of the project](#2-purpose-of-the-project)
3. [Features](#3-features)
4. [Tools and technologies](#4-tools-and-technologies)
5. [File structure](#5-file-structure)
6. [How to run: `run.sh`](#6-how-to-run-runsh)
7. [Quick start](#7-quick-start)
8. [Script reference](#8-script-reference)
9. [Scheduling (systemd timers or cron)](#9-scheduling-systemd-timers-or-cron)
10. [Alerting](#10-alerting)
11. [Testing and CI](#11-testing-and-ci)
12. [Design decisions](#12-design-decisions)
13. [Skills demonstrated](#13-skills-demonstrated)
14. [Roadmap](#14-roadmap)
15. [Further documentation](#15-further-documentation)

---

## 1. Introduction

The **Linux Ops Toolkit** is a set of six command-line tools that a system
administrator or DevOps engineer uses every day on a Linux server:

* **`sysreport`**: is the server healthy (CPU, memory, disk, ports, failed services)?
* **`netcheck`**: can it reach the things it depends on (DNS, TCP, HTTP)?
* **`backup`**: take verified, compressed backups and delete old ones.
* **`logwatch`**: what is happening in the web server and SSH logs?
* **`service_watchdog`**: restart a crashed service automatically, but safely.
* **`user_audit`**: are there risky user accounts on this machine?

Every tool can run by hand, from cron/systemd on a schedule, or as a
monitoring check, because each one prints a clear report **and** returns
a meaningful exit code. Failures can be pushed to Slack/Teams through a
webhook.

## 2. Purpose of the project

**Problem it solves.** Most server incidents start with the same
questions: *Is the box overloaded? Is the disk full? Can it reach the
database? Did the service crash? Who is trying to log in?* Answering them
by hand means remembering a dozen commands under pressure. This toolkit
answers each question with one command and a consistent output.

**Goals**

| Goal | How the project meets it |
|---|---|
| Automate routine admin work | Backups, health reports and service restarts run on systemd timers |
| Detect problems early | Thresholds on disk, load, 5xx ratio and SSH brute force, with exit codes and alerts |
| Be safe to run in production | Strict Bash modes, atomic backup writes, restart rate limits, no root unless needed |
| Be trustworthy | ShellCheck on every script, 18 automated Bats tests, CI on every push |
| Teach the fundamentals | `docs/` explains Linux troubleshooting, networking and scheduling step by step |

**Who it is for:** beginners learning Linux administration and Bash, and
anyone who wants a small, tested set of ops scripts for their own servers.

**Where it fits:** projects 2 to 5 reuse these ideas (health checks, exit
codes, log scanning, scheduled jobs) inside containers, Ansible roles and
CI/CD pipelines.

## 3. Features

| Script | Purpose | Exit codes |
|---|---|---|
| `sysreport.sh` | CPU load vs cores, memory, disk usage, listening ports, failed systemd units, top processes. Text or `--json` output | `0` ok, `1` warnings, `2` bad usage |
| `netcheck.sh` | DNS resolution, raw TCP connect (via `/dev/tcp`) with latency, HTTP status and response time | number of failed checks |
| `backup.sh` | `tar.gz` backups with SHA-256 checksum, integrity verification, exclude patterns and retention | `0` ok, `1` failure (alert sent) |
| `logwatch.sh` | Nginx access log summary (status classes, top IPs/paths, 5xx ratio) and SSH auth log summary (brute-force sources, targeted users, sudo use) | `1` when thresholds are breached |
| `service_watchdog.sh` | Checks a service (systemd or process) and optional HTTP health URL, restarts it, rate-limits restarts per hour, alerts | `0` healthy/recovered, `1` restart failed, `2` limit reached |
| `user_audit.sh` | Lists login-capable users, UID 0 accounts, sudo/wheel members, empty passwords | `1` on risky findings |

Shared behaviour (in `lib/common.sh`): timestamped colour logs to stderr,
`NO_COLOR` support, dependency checks, and webhook alerts.

## 4. Tools and technologies

### Required to run

| Tool | Version | Used for | Install |
|---|---|---|---|
| Linux with systemd | Ubuntu 22.04 / 24.04 tested | running the scripts and timers | – |
| Bash | 4+ | every script | preinstalled |
| coreutils: `awk`, `tar`, `sha256sum` | any | reports, backups, checksums | preinstalled |
| `curl` | any | HTTP checks, webhook alerts | `sudo apt install curl` |
| `getent`, `ss` (iproute2) | any | DNS lookups, listening ports | preinstalled on Ubuntu |

### Required to develop and test

| Tool | Used for | Install |
|---|---|---|
| ShellCheck | static analysis of every script (`./run.sh lint`) | `sudo apt install shellcheck` / `brew install shellcheck` |
| Bats | automated tests (`./run.sh test`) | `sudo apt install bats` / `brew install bats-core` |
| make (optional) | `Makefile` targets | `sudo apt install make` |

> The tools target **Linux**. On macOS, `./run.sh doctor` will report the
> missing Linux-only commands; use an Ubuntu VM or container to run them.

### Technology stack

| Category | Technologies |
|---|---|
| Language | Bash (arrays, traps, `getopts`, process substitution, `/dev/tcp`) |
| Operating system | Linux: `/proc`, users and groups, `/etc/passwd`, `/etc/shadow` |
| Scheduling | systemd services and timers, cron |
| Networking | DNS, TCP, HTTP, latency measurement |
| Alerting | Webhooks (Slack, Microsoft Teams, Mattermost) |
| Quality | ShellCheck, Bats, GitHub Actions |

## 5. File structure

```
01-linux-ops-toolkit/
├── run.sh                        # ★ single entry point: ./run.sh help
├── install.sh                    # installs to /opt/ops-toolkit, links commands into /usr/local/bin,
│                                 #   --timers enables systemd timers, --uninstall removes everything
├── Makefile                      # make lint | test | check | install
├── README.md                     # this document
├── .shellcheckrc                 # ShellCheck settings
│
├── bin/                          # the six commands
│   ├── sysreport.sh              # one-shot health report (text or --json)
│   ├── netcheck.sh               # DNS -> TCP -> HTTP reachability checks
│   ├── backup.sh                 # tar.gz + SHA-256 backups with retention and --verify
│   ├── logwatch.sh               # nginx access log and SSH auth log summaries
│   ├── service_watchdog.sh       # health check + rate-limited restart + alert
│   └── user_audit.sh             # UID 0, sudoers, empty passwords, login users
│
├── lib/
│   └── common.sh                 # shared helpers: logging, colours, dependency checks, webhook alerts
│
├── systemd/                      # scheduling with systemd
│   ├── ops-sysreport.service     # runs sysreport --json
│   ├── ops-sysreport.timer       # every 15 minutes
│   ├── ops-backup.service        # runs backup.sh with settings from the env file
│   ├── ops-backup.timer          # daily at 02:30 with random jitter
│   └── ops-toolkit.env           # settings, installed as /etc/default/ops-toolkit
│
├── cron/
│   └── ops-toolkit.cron          # cron alternative to the timers (/etc/cron.d)
│
├── tests/
│   ├── toolkit.bats              # 18 Bats tests
│   └── fixtures/                 # fake data so tests never touch real system files
│       ├── access.log            #   sample nginx access log
│       ├── auth.log              #   sample SSH auth log with a brute-force attempt
│       ├── passwd                #   sample /etc/passwd with a rogue UID 0 user
│       └── group                 #   sample /etc/group
│
├── docs/
│   ├── SCRIPTS_REFERENCE.md      # every option, environment variable and exit code
│   ├── SCHEDULING.md             # systemd timers vs cron, installing, debugging
│   ├── LINUX_TROUBLESHOOTING.md  # triage for CPU, memory, disk, services and logs
│   └── NETWORKING_BASICS.md      # TCP/IP, ports, DNS, debugging each layer
│
└── .github/workflows/ci.yml      # GitHub Actions: ShellCheck + Bats on every push / PR
```

## 6. How to run: `run.sh`

`run.sh` is the single entry point for this project. It works from any
directory, checks that the tools it needs are installed, and does not
need `make`.

| Command | What it does |
|---|---|
| `./run.sh help` | List all commands |
| `./run.sh doctor` | Check required tools (warns if not on Linux) |
| `./run.sh lint` | ShellCheck every script |
| `./run.sh test` | Run the 18 Bats tests |
| `./run.sh check` | Lint + test |
| `./run.sh demo` | Run `sysreport`, a sample `netcheck` and `logwatch` on the fixture log |
| `./run.sh sysreport [--json]` | Health report |
| `./run.sh netcheck <targets>` | e.g. `dns:github.com tcp:github.com:443 http:https://github.com` |
| `./run.sh backup <args>` | e.g. `-s /etc -d /tmp/backups -k 7` |
| `./run.sh logwatch <args>` | e.g. `auth tests/fixtures/auth.log` |
| `./run.sh watchdog <args>` | e.g. `-n nginx -u http://localhost/ -m 3` |
| `./run.sh audit` | User security audit (use `sudo` for full results) |
| `./run.sh install` | Install system-wide (sudo) |
| `./run.sh install-timers` | Install and enable the systemd timers (sudo) |
| `./run.sh uninstall` | Remove the toolkit and timers (sudo) |

From the portfolio root you can also run `./run.sh 01 <command>`.

## 7. Quick start

```bash
git clone https://github.com/Mian-Basam/linux-ops-toolkit.git
cd linux-ops-toolkit

./run.sh doctor                # 1. check tools
./run.sh check                 # 2. lint + run all tests
./run.sh demo                  # 3. try the commands straight from the repo
./run.sh install-timers        # 4. optional: install system-wide and enable schedules
```

After installing, the commands are on your `PATH` without the `.sh`
suffix (`sysreport`, `netcheck`, `backup`, ...).

## 8. Script reference

Full option tables are in [docs/SCRIPTS_REFERENCE.md](docs/SCRIPTS_REFERENCE.md).
Below are typical runs.

### sysreport.sh

```
$ ./bin/sysreport.sh
=== System report: web01 @ Tue Nov 17 10:00:00 UTC 2026 ===
Kernel   : Linux 6.8.0-45-generic
Uptime   : up 12 days, 3 hours
Load     : 0.42 0.38 0.30 (cores: 4)
Memory   : 61% used of 7.7G
Disks    :
  /                          52%
  /var                       88%
Ports    : 22,80,443,9100
Failed   : none

WARNINGS:
  - disk /var at 88%
```

`--json` produces machine-readable output for dashboards or other tools:

```json
{ "host": "web01", "load": {"1m": 0.42, "5m": 0.38, "15m": 0.3, "cores": 4},
  "memory_used_pct": 61, "disks": [{"mount": "/var", "used_pct": 88}],
  "listening_ports": [22, 80, 443, 9100], "failed_units": [],
  "warnings": ["disk /var at 88%"], "status": "warn" }
```

### netcheck.sh

```
$ ./bin/netcheck.sh -f targets.txt
OK    dns   db.internal                              10.10.20.5
OK    tcp   db.internal:5432                         connected in 2ms
FAIL  tcp   cache.internal:6379                      closed/filtered or timeout (3s)
OK    http  https://app.internal/health              HTTP 200 in 0.041s
---
4 checks, 1 failed
```

The checks run in layers on purpose: if **DNS** fails, nothing else will
work; if DNS works but **TCP** fails, suspect a firewall or a stopped
service; if TCP works but **HTTP** fails, the problem is in the application.

### backup.sh

```
$ ./bin/backup.sh -s /etc -d /var/backups -k 14 -e '*.swp'
[INFO] backing up /etc -> /var/backups/etc_20261117_023000.tar.gz
[INFO] verified OK: /var/backups/etc_20261117_023000.tar.gz
[INFO] size: 1.2M
[INFO] done (1 pruned, keeping 14)

$ ./bin/backup.sh --verify /var/backups/etc_20261117_023000.tar.gz
[INFO] verified OK
```

The archive is written to a `.partial` file and renamed only after `tar`
succeeds, so a crash never leaves a half-written archive that looks valid.

### logwatch.sh

```
$ ./bin/logwatch.sh auth /var/log/auth.log
failed SSH password attempts : 4
accepted SSH logins          : 1
sudo commands                : 1
-- top 5 source IPs of failed logins --
      3 203.0.113.9
      1 198.51.100.7
-- top 5 targeted users --
      2 root
      1 deploy
      1 admin
```

### service_watchdog.sh

```bash
# restart nginx if it is down or / stops returning 2xx; max 3 restarts per hour
./bin/service_watchdog.sh -n nginx -u http://localhost/ -m 3
```

The restart limit prevents a crash loop from hiding a real problem; once
the limit is hit, the script stops restarting and sends an alert so a
person can investigate.

### user_audit.sh

```bash
sudo ./bin/user_audit.sh      # exits 1 if it finds an extra UID 0 account or empty password
```

## 9. Scheduling (systemd timers or cron)

`./run.sh install-timers` (or `sudo ./install.sh --timers`) installs and enables:

| Unit | Schedule | What it does |
|---|---|---|
| `ops-sysreport.timer` | every 15 min | writes `/var/log/ops-toolkit/sysreport.json` |
| `ops-backup.timer` | daily 02:30 (±10 min jitter) | backs up `$BACKUP_SOURCE`, keeps `$BACKUP_KEEP` |

Settings live in `/etc/default/ops-toolkit`. A cron version is in
`cron/ops-toolkit.cron`. See [docs/SCHEDULING.md](docs/SCHEDULING.md) for
the comparison and how to debug timers (`systemctl list-timers`,
`journalctl -u ops-backup`).

## 10. Alerting

Set `ALERT_WEBHOOK_URL` (Slack, Microsoft Teams, Mattermost or any endpoint
accepting `{"text": "..."}`) and the scripts post on failures: backup
errors, watchdog restarts, high 5xx ratio and SSH brute force.

## 11. Testing and CI

```bash
./run.sh lint   # ShellCheck on every script
./run.sh test   # 18 Bats tests
```

The tests use fixture files and temporary directories, so they never touch
real system files. They cover the happy path and the failure paths: tampered
archives, retention limits, closed ports, restart rate-limits and malicious
UID 0 accounts. GitHub Actions runs both on every push and pull request.

## 12. Design decisions

* **Exit codes are the API.** Every script returns a meaningful status, so it
  can be chained in pipelines, cron, or used as a monitoring check.
* **`set -Eeuo pipefail`** where a partial run is dangerous (backups), plain
  `set -uo pipefail` where the script must continue after a failed check.
* **No root unless needed.** Only `install.sh` and the shadow-file check in
  `user_audit.sh` require it.
* **Testable by design.** File paths (`--passwd`, `--group`) and state dirs
  are overridable so tests can use fixtures.

## 13. Skills demonstrated

| Area | Where |
|---|---|
| Linux administration | `/proc`, `df`, `ss`, systemd units and timers, cron, users/groups |
| Bash scripting | argument parsing, traps, arrays, process substitution, `/dev/tcp` |
| Networking fundamentals | DNS → TCP → HTTP layered checks, latency measurement |
| Automation | scheduled jobs, self-healing watchdog, webhook alerts |
| Quality | ShellCheck, Bats tests, GitHub Actions CI |
| Security | SSH brute-force detection, UID 0 and sudo audit |
| Documentation | this README and `docs/` |

## 14. Roadmap

- [ ] Package as a `.deb` with `nfpm`
- [ ] Push `sysreport --json` to a Prometheus Pushgateway
- [ ] Remote backups to S3-compatible storage (MinIO)

## 15. Further documentation

| Document | Contents |
|---|---|
| [docs/SCRIPTS_REFERENCE.md](docs/SCRIPTS_REFERENCE.md) | Every option, environment variable and exit code |
| [docs/SCHEDULING.md](docs/SCHEDULING.md) | systemd timers vs cron, installing, debugging |
| [docs/LINUX_TROUBLESHOOTING.md](docs/LINUX_TROUBLESHOOTING.md) | Step-by-step triage for CPU, memory, disk, services and logs |
| [docs/NETWORKING_BASICS.md](docs/NETWORKING_BASICS.md) | TCP/IP, ports, DNS and how to debug each layer |

---

**Author:** Basil Ahtisham · [LinkedIn](https://linkedin.com/in/mianbasil) · [GitHub](https://github.com/Mian-Basam)
