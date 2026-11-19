# Linux Troubleshooting Playbook

A repeatable order for investigating a misbehaving server. Start with
`sysreport.sh`, then go deeper into the area it flags.

## 0. First minute

```bash
uptime                       # load averages
free -h                      # memory
df -h; df -i                 # disk space AND inodes
systemctl --failed           # crashed services
journalctl -p err -S -1h     # errors in the last hour
```

## 1. High CPU / load

```bash
top -o %CPU                  # who is using CPU (press 1 for per-core)
ps -eo pid,comm,%cpu --sort=-%cpu | head
vmstat 1 5                   # r = run queue, wa = waiting on I/O
```

* High load with low CPU use and high `wa` means the bottleneck is **disk I/O**, not CPU. Check with `iostat -x 1`.
* A load average above the core count means processes are waiting.

## 2. Memory

```bash
free -h                      # look at "available", not "free"
ps -eo pid,comm,rss --sort=-rss | head
dmesg -T | grep -i -E 'oom|killed process'
```

If the OOM killer has fired, the kernel log names the process it killed.

## 3. Disk full

```bash
df -h                                    # which filesystem
sudo du -xh --max-depth=1 /var | sort -h # what is large
sudo find / -xdev -size +500M -ls 2>/dev/null
sudo lsof +L1                            # deleted files still held open
```

* **Deleted but still open:** a process keeps writing to a log you deleted.
  The space returns only after restarting that process.
* **`df -i` at 100%:** out of inodes (millions of tiny files), even with free space.
* Quick wins: `journalctl --vacuum-size=200M`, `docker system prune`,
  `apt-get clean`, rotate logs with `logrotate`.

## 4. Service will not start

```bash
systemctl status nginx
journalctl -u nginx -n 100 --no-pager
nginx -t                     # many daemons have a config test flag
ss -ltnp | grep ':80 '       # is another process already on the port?
```

## 5. Network

See [NETWORKING_BASICS.md](NETWORKING_BASICS.md). Short version:

```bash
./bin/netcheck.sh dns:host tcp:host:port http:http://host/health
```

## 6. Logs

| Log | Location (Debian/Ubuntu) |
|---|---|
| System | `journalctl`, `/var/log/syslog` |
| Auth / SSH | `/var/log/auth.log` |
| Kernel | `dmesg -T` |
| Nginx | `/var/log/nginx/{access,error}.log` |

```bash
journalctl -u nginx -S "2026-11-17 09:00" -U "2026-11-17 10:00"
tail -F /var/log/nginx/error.log
```

## 7. After the incident

* Write down the timeline, root cause and fix.
* Add a check (to `sysreport.sh`, monitoring, or an alert) so the same
  problem is caught earlier next time.
