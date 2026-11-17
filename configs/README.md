# Example configuration files

Sanitized samples matching [docs/architecture.md](../docs/architecture.md).  
Replace `<CHANGE_ME>`, `<PRIVATE_KEY>` and `<PUBLIC_KEY>` before use. **Do not commit real secrets.**

## Layout

| Path | What it is |
| --- | --- |
| [wireguard/wg0-site-a.conf](wireguard/wg0-site-a.conf) | Site A WG (`10.255.50.1`); `AllowedIPs` = Site B/C prefixes |
| [wireguard/wg0-site-b.conf](wireguard/wg0-site-b.conf) | Site B WG (`10.255.50.2`); does **not** pin VIP only to Site A |
| [wireguard/wg0-site-c.conf](wireguard/wg0-site-c.conf) | Site C WG (`10.255.50.3`) |
| [keepalived/keepalived-master.conf](keepalived/keepalived-master.conf) | Preferred owner: **state BACKUP**, priority 150, unicast VRRP, VIP `10.99.0.10/32`, `notify_*` |
| [keepalived/keepalived-backup.conf](keepalived/keepalived-backup.conf) | Site B priority 130 + `notify_*` |
| [keepalived/keepalived-site-c.conf](keepalived/keepalived-site-c.conf) | Site C priority 110 + `notify_*` |
| [keepalived/notify-vip-wg.sh](keepalived/notify-vip-wg.sh) | MASTER/BACKUP/FAULT: `wg set` AllowedIPs + host route for VIP |
| [keepalived/notify-vip-wg.env.example](keepalived/notify-vip-wg.env.example) | Env template for the notify script |
| [haproxy/haproxy.cfg](haproxy/haproxy.cfg) | `:80` → three site app VMs; stats on `127.0.0.1:8404` |
| [mariadb-galera/60-galera.cnf](mariadb-galera/60-galera.cnf) | Galera ring `.10.40.21` / `.20.40.21` / `.30.40.21` |
| [proxmox/network-interfaces.example](proxmox/network-interfaces.example) | VLANs on `eno1`/`eno2` (no single-slave bond) |
| [proxmox/corosync.conf.example](proxmox/corosync.conf.example) | knet-style reference; do not hand-edit live clusters |
| [scripts/check-galera.sh](scripts/check-galera.sh) | Galera health helper (executable bit set in git) |

## Consistency checklist

| Item | Example value |
| --- | --- |
| Site A prefixes | `10.10.10/20/30/40.0/24` |
| Site B prefixes | `10.20.10/20/30/40.0/24` |
| Site C prefixes | `10.30.10/20/30/40.0/24` |
| Site routers (`.1` + WG) | `10.10.x.1` / `10.20.x.1` / `10.30.x.1` + `10.255.50.1–3` |
| App / Galera VMs | `10.10.40.21`, `10.20.40.21`, `10.30.40.21` |
| Floating VIP | `10.99.0.10/32` (dynamic AllowedIPs only) |
| WireGuard overlay | `10.255.50.1–3` |
| WAN endpoints (docs only) | `192.0.2.10`, `.20`, `.30` |
| Keepalived `auth_pass` | 8 characters max (`ChgMe_01` placeholder) |

## VIP after failover

Static `wg0-site-*.conf` AllowedIPs = **site prefixes only** (no `10.99.0.10/32`). Keepalived `notify_*` → [`notify-vip-wg.sh`](keepalived/notify-vip-wg.sh) adds/withdraws the VIP `/32` on site routers via `wg set … allowed-ips` plus `ip route`. A kernel route alone is not enough (WireGuard cryptokey routing). Details: [docs/architecture.md](../docs/architecture.md).
