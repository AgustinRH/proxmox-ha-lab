# Architecture — network, VLANs and IP plan

All addresses below are **examples** (RFC 1918 / RFC 5737). Replace with your plan; never commit production IPs or DNS names.

## Sites and roles

| Site | Proxmox node (example) | Services prefix | Role notes |
| --- | --- | --- | --- |
| Site A | `pve-a` | `10.10.0.0/16` style `/24`s below | Preferred VIP owner (highest Keepalived priority) |
| Site B | `pve-b` | `10.20.x.0/24` | Second in VIP preference chain |
| Site C | `pve-c` | `10.30.x.0/24` | Third site; full peer in the same Proxmox cluster |

There is **no stretched L2** between sites. Each site owns distinct RFC1918 `/24`s. VRRP uses **unicast** peers. WireGuard carries inter-site traffic with `AllowedIPs` set to those site prefixes (not a shared `10.10.40.0/24` everywhere).

Production can place **two** hypervisors per site for extra capacity; this portfolio documents **one node per site**. Scale the same patterns when you add nodes.

## Physical links

Each Proxmox node:

| Link | Speed | VLANs (example) |
| --- | --- | --- |
| NIC 0 (`eno1`) | 10GbE | VLAN 10 mgmt + VLAN 40 services |
| NIC 1 (`eno2`) | 10GbE | VLAN 20 cluster/Corosync + VLAN 30 storage |

**Bonding:** the published `configs/proxmox/network-interfaces.example` does **not** use bonding. Each NIC carries its VLAN subinterfaces directly, matching the split above. If you later team two NICs per fabric, LACP/`802.3ad` needs **at least two slaves per bond** and matching switch config — that remains a deployment-specific **TODO**, not part of this example.

## VLAN segmentation (same VLAN IDs, different prefixes per site)

| VLAN ID | Name | Purpose | Site A | Site B | Site C |
| --- | --- | --- | --- | --- | --- |
| 10 | `mgmt` | Proxmox UI/SSH, monitoring | `10.10.10.0/24` | `10.20.10.0/24` | `10.30.10.0/24` |
| 20 | `cluster` | Corosync only | `10.10.20.0/24` | `10.20.20.0/24` | `10.30.20.0/24` |
| 30 | `storage` | PBS / backup path | `10.10.30.0/24` | `10.20.30.0/24` | `10.30.30.0/24` |
| 40 | `services` | App VMs | `10.10.40.0/24` | `10.20.40.0/24` | `10.30.40.0/24` |

WireGuard overlay (not a site LAN): `10.255.50.0/24` (example peer addresses `.1` / `.2` / `.3`).

Do not mix Corosync onto a congested user VLAN. Keep mgmt reachable if services VLAN misbehaves.

## Example IP plan

### Hypervisors

| Host | Mgmt | Cluster | Optional storage host IP | Gateway (mgmt) |
| --- | --- | --- | --- | --- |
| `pve-a` | `10.10.10.11` | `10.10.20.11` | `10.10.30.11` | `10.10.10.1` |
| `pve-b` | `10.20.10.11` | `10.20.20.11` | `10.20.30.11` | `10.20.10.1` |
| `pve-c` | `10.30.10.11` | `10.30.20.11` | `10.30.30.11` | `10.30.10.1` |

Public / WAN examples (documentation only): `192.0.2.10`, `192.0.2.20`, `192.0.2.30` (RFC 5737 TEST-NET-1).

### Guests

| VM | IP | Notes |
| --- | --- | --- |
| `webdb-a1` | `10.10.40.21` | Site A app + Galera member `galera-a1` (same VM) |
| `webdb-b1` | `10.20.40.21` | Site B app + `galera-b1` |
| `webdb-c1` | `10.30.40.21` | Site C app + `galera-c1` |
| `pbs-a` / `pbs-b` / `pbs-c` | `10.10.30.21` / `10.20.30.21` / `10.30.30.21` | PBS on storage VLAN |

Guest vCPU / RAM / disk: **TODO** (fill from your inventory).

Optional second app VM per site (e.g. `10.10.40.22`) can be added later; published configs use the three primaries above.

### Service VIP (floating, not inside one site `/24`)

| Name | Address | Notes |
| --- | --- | --- |
| Application VIP | `10.99.0.10/32` | Keepalived secondary address on the winning app VM |

#### How the VIP is reached after failover

1. **Keepalived (unicast VRRP)** moves `10.99.0.10/32` onto whichever app VM currently wins (priority + HAProxy health). There is no shared L2, so every instance sets `unicast_src_ip` and `unicast_peer` to the other app VMs’ services addresses.
2. **Local clients on the winning site** reach `10.99.0.10` as a local address on that VM (or via the site router).
3. **Clients on other sites** need a route for `10.99.0.10/32` toward the site that currently owns the VIP (typically via WireGuard to that site’s gateway/`webdb`).  
   - Static example configs **do not** pin `10.99.0.10/32` under only Site A’s peer.  
   - **TODO:** how you inject/withdraw that `/32` (manual route on failover drill, DNS update, or dynamic routing). Document your chosen method in private ops notes.
4. HAProxy on the VIP owner listens on `:80` and load-balances to the three app backends over the WireGuard-connected services prefixes.

### WireGuard overlay

| Peer | Interface `Address` | `AllowedIPs` to that peer (site prefixes) |
| --- | --- | --- |
| Site A | `10.255.50.1/24` | `10.10.10.0/24`, `10.10.20.0/24`, `10.10.30.0/24`, `10.10.40.0/24` |
| Site B | `10.255.50.2/24` | `10.20.10.0/24`, `10.20.20.0/24`, `10.20.30.0/24`, `10.20.40.0/24` |
| Site C | `10.255.50.3/24` | `10.30.10.0/24`, `10.30.20.0/24`, `10.30.30.0/24`, `10.30.40.0/24` |

Private keys: `<PRIVATE_KEY>` / `<PUBLIC_KEY>` — never commit. WAN endpoints in samples: `192.0.2.10`, `.20`, `.30`.

## Logical data path

1. Client → VIP `10.99.0.10` (on the current Keepalived winner).
2. **HAProxy** on that same VM distributes to healthy `webdb-*` backends (`:8080`).
3. PHP talks to **ProxySQL** on `127.0.0.1:6033` (application DB user).
4. ProxySQL prefers local MariaDB; Galera certifies across `10.10.40.21` / `10.20.40.21` / `10.30.40.21`.
5. **Syncthing** keeps the web document root aligned; **Gitea** is the git source of truth.

## Storage notes

- VM disks live on **local LVM-thin** (or equivalent) on each node’s data disk — not on the OS system VG by default.
- Each Proxmox node backs up to **its own** PBS datastore. One job cannot target PBS instances that only exist on other nodes.
- Optional monitoring HA / ZFS: **TODO** if you publish that piece.

## Related docs

- Failover behaviour: [failover.md](failover.md)
- PBS: [backup-and-restore.md](backup-and-restore.md)
- Day-2 ops: [runbook.md](runbook.md)
