# Script Reference

All scripts print logs to **stderr** and results to **stdout**, so you can
pipe results without the log noise: `sysreport.sh --json 2>/dev/null | jq .`

Common environment variables:

| Variable | Used by | Meaning |
|---|---|---|
| `NO_COLOR` | all | disable coloured output |
| `ALERT_WEBHOOK_URL` | backup, logwatch, watchdog | JSON webhook for alerts |

---

## sysreport.sh

| Option | Default | Description |
|---|---|---|
| `--json` | off | Machine-readable output |
| `--disk-warn PCT` | 85 | Warn when any filesystem is at or above this % |
| `--mem-warn PCT` | 90 | Warn when memory use is at or above this % |

Checks performed:

* **Load** – 5-minute load average compared with `nproc`. A load above the
  core count means work is queuing for CPU (or waiting on disk I/O).
* **Memory** – uses `MemAvailable` (not `MemFree`), because Linux uses free
  RAM for page cache, and that cache is reclaimable.
* **Disk** – `df -P`, skipping `tmpfs`, `devtmpfs`, `overlay`, `squashfs`.
* **Ports** – `ss -ltn` listening TCP ports.
* **Failed units** – `systemctl --failed` when systemd is running.

Exit: `0` healthy · `1` one or more warnings · `2` bad option.

---

## netcheck.sh

```
netcheck.sh [-f FILE] [TARGET ...]
```

| Target | Example | Check |
|---|---|---|
| `dns:NAME` | `dns:db.internal` | `getent ahosts` resolves to one or more IPs |
| `tcp:HOST:PORT` | `tcp:10.0.0.5:5432` | TCP handshake via Bash `/dev/tcp`, reports latency |
| `http:URL` | `http:https://app/health` | HTTP status must be 2xx/3xx; reports total time |

`NETCHECK_TIMEOUT` (default 3s) applies per check. In a targets file, blank
lines and `#` comments are ignored. Exit code = number of failures (max 125).

---

## backup.sh

```
backup.sh -s SOURCE -d DEST [-k KEEP] [-e PATTERN]...
backup.sh --verify ARCHIVE
```

| Option | Default | Description |
|---|---|---|
| `-s` | – | Directory to back up (required) |
| `-d` | – | Destination directory, created if missing (required) |
| `-k` | 7 | Number of newest archives of this source to keep |
| `-e` | – | `tar --exclude` pattern, repeatable |
| `--verify` | – | Re-check checksum and archive readability |

Output files: `NAME_YYYYMMDD_HHMMSS.tar.gz` and a matching `.sha256`.

Restore:

```bash
backup.sh --verify /var/backups/etc_20261117_023000.tar.gz
sudo tar -xzf /var/backups/etc_20261117_023000.tar.gz -C /tmp/restore
```

Always restore to a temporary directory first and compare before overwriting live files.

---

## logwatch.sh

```
logwatch.sh nginx FILE [TOP_N]
logwatch.sh auth  FILE [TOP_N]
```

* **nginx** expects the default *combined* log format. Exits `1` when the
  5xx ratio is above 5%.
* **auth** reads Debian/Ubuntu `auth.log` (on RHEL use `/var/log/secure`).
  Exits `1` when failed logins exceed `SSH_FAIL_THRESHOLD` (default 20).

---

## service_watchdog.sh

| Option | Default | Description |
|---|---|---|
| `-n NAME` | – | systemd unit name, or process name when systemd is absent |
| `-u URL` | – | Optional health URL that must return 2xx |
| `-r CMD` | `systemctl restart NAME` | Restart command |
| `-m N` | 3 | Max restarts per rolling hour |

Environment: `STATE_DIR` (restart history, default `/tmp/watchdog`),
`WATCHDOG_SETTLE` (seconds to wait after restart, default 3).

Exit: `0` healthy or recovered · `1` still unhealthy after restart · `2` restart limit reached.

---

## user_audit.sh

| Option | Default |
|---|---|
| `--passwd FILE` | `/etc/passwd` |
| `--group FILE` | `/etc/group` |
| `--shadow FILE` | `/etc/shadow` (needs root) |

Exits `1` if any non-root account has UID 0 or any account has an empty password hash.
