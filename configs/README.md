# Example configuration files

Sanitized samples that match the IP plan in [docs/architecture.md](../docs/architecture.md).  
Every important line is commented in the files themselves. Replace `<CHANGE_ME>`, `<PRIVATE_KEY>` and `<PUBLIC_KEY>` before use. **Do not commit real secrets.**

## Layout

| Path | What it is |
| --- | --- |
| [wireguard/wg0-site-a.conf](wireguard/wg0-site-a.conf) | WireGuard peer for Site A (`10.10.50.1`), endpoints `192.0.2.x` |
| [wireguard/wg0-site-b.conf](wireguard/wg0-site-b.conf) | Same for Site B (`10.10.50.2`) |
| [wireguard/wg0-site-c.conf](wireguard/wg0-site-c.conf) | Same for Site C (`10.10.50.3`) |
| [keepalived/keepalived-master.conf](keepalived/keepalived-master.conf) | Preferred VIP owner (`10.10.40.10`), HAProxy health check |
| [keepalived/keepalived-backup.conf](keepalived/keepalived-backup.conf) | Lower-priority peer template |
| [haproxy/haproxy.cfg](haproxy/haproxy.cfg) | HTTP frontend on :80 → `webdb-a1/b1/c1:8080`, stats with placeholder auth |
| [mariadb-galera/60-galera.cnf](mariadb-galera/60-galera.cnf) | Galera `wsrep_*` for the 3-node ring `.21` / `.31` / `.41` |
| [proxmox/network-interfaces.example](proxmox/network-interfaces.example) | Dual 10GbE bonds, VLAN 10/20/30/40 bridges (`pve-a`) |
| [proxmox/corosync.conf.example](proxmox/corosync.conf.example) | 3-node Corosync on `10.10.20.11–13` |
| [scripts/check-galera.sh](scripts/check-galera.sh) | Prints cluster status / size / sync; exit 0 when healthy |

## How these fit together

1. **Proxmox hosts** get `network-interfaces.example` + join the cluster described by `corosync.conf.example`.
2. **Site routers / WG gateways** load the `wg0-site-*.conf` files so Corosync, Galera and Syncthing can cross sites.
3. **App VMs** run MariaDB with `60-galera.cnf`, HAProxy with `haproxy.cfg`, and Keepalived so `10.10.40.10` floats to a healthy node.
4. Operators run `scripts/check-galera.sh` during failover drills ([docs/failover.md](../docs/failover.md)).

## Consistency checklist

| Item | Example value |
| --- | --- |
| Service VIP | `10.10.40.10` |
| Galera / HTTP primaries | `10.10.40.21`, `10.10.40.31`, `10.10.40.41` |
| Proxmox mgmt | `10.10.10.11–13` |
| Corosync | `10.10.20.11–13` |
| PBS | `10.10.30.21–23` |
| WireGuard | `10.10.50.1–3` |
| Public endpoints (docs only) | `192.0.2.10`, `.20`, `.30` |
