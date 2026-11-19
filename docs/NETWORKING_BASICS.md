# Networking Basics for Operations

## The TCP/IP model

| Layer | Examples | Tool to test it |
|---|---|---|
| Application | HTTP, DNS, SSH | `curl -v`, `dig`, `ssh -v` |
| Transport | TCP, UDP, ports | `ss -ltn`, `nc -zv host port`, `netcheck.sh tcp:` |
| Internet | IP, routing, ICMP | `ip addr`, `ip route`, `ping`, `traceroute` |
| Link | Ethernet, MAC, ARP | `ip link`, `ip neigh` |

Debug **bottom-up**: there is no point checking HTTP if the route is missing.

## IP addressing

* `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` are private ranges.
* `/24` = 255.255.255.0 = 256 addresses (254 usable hosts).
* The **default gateway** is where packets go when no specific route matches: `ip route show default`.

## TCP

* Connection setup is the **three-way handshake**: SYN → SYN-ACK → ACK.
* **Connection refused**: the host answered, but nothing listens on that port (service down or wrong port).
* **Timeout**: no answer at all, usually a firewall dropping packets or a routing problem.
* Common ports: 22 SSH, 53 DNS, 80 HTTP, 443 HTTPS, 3306 MySQL, 5432 PostgreSQL, 6379 Redis, 9090 Prometheus, 10050/10051 Zabbix.

```bash
ss -ltnp                 # what is listening, and which process
ss -tnp state established
sudo tcpdump -i any port 5432 -nn   # watch the actual packets
```

## UDP

No handshake, no delivery guarantee. DNS queries use UDP 53 (TCP for large responses).

## DNS

Resolution order on Linux is defined in `/etc/nsswitch.conf`
(usually `files dns`): first `/etc/hosts`, then the servers in `/etc/resolv.conf`.

| Record | Purpose |
|---|---|
| A / AAAA | name → IPv4 / IPv6 |
| CNAME | alias to another name |
| MX | mail server |
| PTR | reverse lookup (IP → name) |
| TXT | free text (SPF, verification) |

```bash
getent hosts app.internal          # uses the same path as applications
dig app.internal +short            # asks DNS directly (skips /etc/hosts)
dig @10.0.0.2 app.internal         # ask a specific DNS server
```

If `getent` and `dig` disagree, check `/etc/hosts`.

## Firewall

```bash
sudo ufw status verbose           # Ubuntu
sudo iptables -L -n -v            # underlying rules
sudo firewall-cmd --list-all      # RHEL/CentOS
```

## A worked example

"The app cannot reach the database":

```
$ netcheck.sh dns:db.internal tcp:db.internal:5432
OK    dns   db.internal          10.10.20.5
FAIL  tcp   db.internal:5432     closed/filtered or timeout (3s)
```

DNS works and TCP times out, so check in this order: is PostgreSQL running
and listening on the right interface (`ss -ltn` on the DB server;
`listen_addresses` in `postgresql.conf`)? Is a firewall on either host
dropping 5432? Is there a route between the subnets?
