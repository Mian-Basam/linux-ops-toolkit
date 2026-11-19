# Scheduling: systemd timers vs cron

## Comparison

| | systemd timer | cron |
|---|---|---|
| Logs | `journalctl -u ops-backup` automatically | must redirect output yourself |
| Missed runs (server was off) | `Persistent=true` runs them on boot | skipped |
| Avoiding thundering herd | `RandomizedDelaySec=` | manual `sleep $RANDOM` |
| Resource control | `Nice=`, `IOSchedulingClass=`, `MemoryMax=` | none |
| Dependencies | `After=network-online.target` | none |
| Simplicity | two files per job | one line per job |

This toolkit ships both. Prefer timers on modern distributions.

## Installing the timers

```bash
sudo ./install.sh --timers
systemctl list-timers 'ops-*'
```

```
NEXT                        LEFT     LAST  PASSED  UNIT                  ACTIVATES
Tue 2026-11-17 10:15:00 UTC 9min     -     -       ops-sysreport.timer   ops-sysreport.service
Wed 2026-11-18 02:34:12 UTC 16h      -     -       ops-backup.timer      ops-backup.service
```

Change what is backed up in `/etc/default/ops-toolkit`, then:

```bash
sudo systemctl restart ops-backup.timer
```

## Running a job now

```bash
sudo systemctl start ops-backup.service
journalctl -u ops-backup.service -n 50 --no-pager
```

## Debugging a timer that does not fire

1. `systemctl status ops-backup.timer` – is it `active (waiting)`?
2. `systemctl list-timers --all` – is `NEXT` set?
3. `systemd-analyze calendar '*-*-* 02:30:00'` – does the expression mean what you think?
4. `journalctl -u ops-backup.service` – did it fire and fail?
5. After editing unit files: `sudo systemctl daemon-reload`.

## Cron

```bash
sudo cp cron/ops-toolkit.cron /etc/cron.d/ops-toolkit
sudo chmod 644 /etc/cron.d/ops-toolkit
grep CRON /var/log/syslog | tail       # confirm cron picked it up
```

Cron runs with a minimal `PATH` and no login environment, so the
crontab uses absolute paths and redirects output to log files.
