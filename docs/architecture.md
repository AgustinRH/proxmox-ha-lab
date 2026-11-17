# Architecture — network, VLANs and IP plan

All addresses below are **examples** (RFC 1918 / RFC 5737). Replace with your plan; never commit production IPs or DNS names.

## Sites and roles

| Site | Proxmox node (example) | Role notes |
| --- | --- | --- |
| Site A | `pve-a` | Preferred VIP owner (highest Keepalived priority on its primary app VM) |
| Site B | `pve-b` | Second in VIP / ops preference chain |
| Site C | `pve-c` | Third site; full peer in the same Proxmox cluster |

Production can place **two** hypervisors per site for extra capacity; this portfolio documents the minimal **one node per site** shape. Scale the same patterns (local PBS, local Galera members, Corosync votes) when you add nodes.

## Physical links

Each Proxmox node:

| Link | Speed | Typical use |
| --- | --- | --- |
| NIC 0 | 10GbE | Tagged trunk: mgmt + services (+ optional WAN handoff) |
| NIC 1 | 10GbE | Tagged trunk: cluster (Corosync) + storage replication / backup |

Bonding mode and switch config: **TODO**.

## VLAN segmentation

| VLAN ID (example) | Name | Purpose | Example CIDR |
| --- | --- | --- | --- |
| 10 | `mgmt` | Proxmox UI/SSH, PBS UI, monitoring agents | `10.10.10.0/24` |
| 20 | `cluster` | Corosync / cluster traffic only | `10.10.20.0/24` |
| 30 | `storage` | Backup and optional disk replication | `10.10.30.0/24` |
| 40 | `services` | App VMs, VIP, Syncthing, Gitea | `10.10.40.0/24` |
| 50 | `vpn-overlay` | WireGuard addressed endpoints (optional dedicated) | `10.10.50.0/24` |

Do not mix Corosync onto a congested user VLAN. Keep mgmt reachable if services VLAN misbehaves.

## Example IP plan

### Hypervisors (mgmt)

| Host | Mgmt IP | Cluster IP | Notes |
| --- | --- | --- | --- |
| `pve-a` | `10.10.10.11` | `10.10.20.11` | Site A |
| `pve-b` | `10.10.10.12` | `10.10.20.12` | Site B |
| `pve-c` | `10.10.10.13` | `10.10.20.13` | Site C |
| Default gateway (per site LAN) | `10.10.10.1` | — | Usually the site router / VPN appliance |

Public / WAN examples (documentation only): `192.0.2.10`, `192.0.2.20`, `192.0.2.30` (RFC 5737 TEST-NET-1).

### Guests per node (services VLAN)

| VM | Example IP | Stack |
| --- | --- | --- |
| `webdb-a1` / `webdb-a2` | `10.10.40.21` / `.22` | Apache, PHP, MariaDB, ProxySQL, HAProxy, Keepalived, Syncthing |
| `webdb-b1` / `webdb-b2` | `10.10.40.31` / `.32` | same |
| `webdb-c1` / `webdb-c2` | `10.10.40.41` / `.42` | same |
| `pbs-a` / `pbs-b` / `pbs-c` | `10.10.30.21` / `.22` / `.23` | Proxmox Backup Server (storage VLAN or mgmt — pick one and stick to it) |

Guest sizing used in a similar production layout (indicative, not a benchmark): app VM ~24 GB RAM / 2 vCPU / ~100 GB disk; PBS VM ~12 GB RAM / 2 vCPU / larger datastore disk. **TODO:** record your exact sizes.

### Service VIP

| Name | Example | Owner |
| --- | --- | --- |
| Application VIP | `10.10.40.10` | Keepalived; preferred on `webdb-a1`, then falling priorities on other app VMs |

HTTP on the VIP is terminated/balanced by HAProxy (port 80 → backends on port 8080 is a common pattern so Apache is not competing for :80 on the VIP host).

### WireGuard overlay (example)

| Peer | WG address | Routes into tunnel |
| --- | --- | --- |
| Site A | `10.10.50.1/32` | Site A LAN prefixes |
| Site B | `10.10.50.2/32` | Site B LAN prefixes |
| Site C | `10.10.50.3/32` | Site C LAN prefixes |

Private keys: `<CHANGE_ME>` — never commit. Endpoint hostnames/IPs: use `192.0.2.x` or `<CHANGE_ME_ENDPOINT>` in published configs.

## Logical data path

1. Client → **VIP** `10.10.40.10`.
2. **Keepalived** ensures the VIP sits on a healthy app VM (HAProxy process check).
3. **HAProxy** distributes to healthy `webdb-*` backends.
4. PHP talks to **ProxySQL** on `127.0.0.1:6033` (not raw `root@3306`).
5. ProxySQL prefers local MariaDB for writes; Galera certifies to the ring.
6. **Syncthing** keeps `/var/www/html` aligned; **Gitea** is the source of truth for git workflows.

## Storage notes

- VM disks live on **local LVM-thin** (or equivalent) on each node’s data disk — not on the OS `local-lvm` by default.
- Each Proxmox node backs up to **its own** PBS datastore (`pbs-a`, `pbs-b`, `pbs-c`). One job cannot target six foreign datastores that only exist on other nodes.
- Optional: ZFS/replication for a monitoring VM with HA affinity — **TODO** if you publish that piece.

## Related docs

- Failover behaviour: [failover.md](failover.md)
- PBS: [backup-and-restore.md](backup-and-restore.md)
- Day-2 ops: [runbook.md](runbook.md)
