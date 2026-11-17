# Runbook — routine operations

Commands are illustrative. Replace hosts and paths. Never paste real passwords into this repo.

## Daily / weekly health

### Proxmox cluster

```bash
pvecm status
# Expect: Quorate: Yes, expected votes = node count (when all up)
```

### Galera (on any app VM)

```bash
mysql --batch --skip-column-names -e \
  "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_status','wsrep_local_state_comment','wsrep_cluster_size');"
```

Expect `Primary`, `Synced`, and size equal to the number of members.

Optional helper script pattern: print `1` only when local node is usable for app traffic.

### Edge

```bash
systemctl is-active haproxy keepalived
# On the VIP owner: ip -br addr | grep <VIP>
curl -fsS -o /dev/null -w '%{http_code}\n' http://10.99.0.10/
```

### WireGuard

```bash
sudo wg show
ping -c 3 10.255.50.2   # Site B overlay peer example
```

## Adding a Proxmox node

1. Install matching Proxmox major version; configure mgmt + cluster NICs/VLANs; set `/etc/hosts` for all members.
2. Sync time (chrony/NTP).
3. From a quorate node: `pvecm add <NEW_NODE_IP>` (or UI join). Resolve certificate prompts carefully.
4. Create local LVM-thin data store; register **local** PBS storage only after PBS VM exists.
5. Join Corosync; confirm `pvecm status` shows the new vote.
6. Deploy app VMs / PBS as needed; add Galera members with `gcomm://…` updated on **all** members; add Keepalived priority without colliding; add Syncthing device with a **new** device ID (cloning disks duplicates IDs).
7. Update monitoring inventory.

If the new node will move to another building later, rehearse the WireGuard + Corosync move procedure in a window (private checklist — **TODO** link).

## Rolling upgrades

### Guests (app / PBS)

1. Backup the VM on its PBS job (or wait for a green run).
2. Upgrade one guest at a time (`apt` on Ubuntu / PBS).
3. Verify Galera join + HAProxy health before the next guest.
4. Prefer upgrading PBS guests in a period with low backup load.

### Proxmox nodes

1. Ensure cluster quorate and backups green.
2. Migrate or accept downtime for local-only VMs on that node.
3. Upgrade one node; reboot if kernel requires; wait until it rejoins Corosync.
4. Proceed to the next site/node.
5. Enterprise vs no-subscription repos: use what your license allows; avoid leaving `apt update` broken on 401s.

## Checking Galera health (deeper)

```bash
mysql -e "SHOW STATUS LIKE 'wsrep_%';"
```

Pay attention to:

| Variable | Healthy direction |
| --- | --- |
| `wsrep_cluster_status` | `Primary` |
| `wsrep_local_state_comment` | `Synced` |
| `wsrep_cluster_size` | Expected member count |
| `wsrep_ready` | `ON` |

If the whole ring is down, follow the single-donor bootstrap process in [failover.md](failover.md) — never two donors.

## ProxySQL note

App connections: `127.0.0.1:6033` with an application DB user — not `root` via socket for PHP. Stale PID files can make ProxySQL believe it is running while nothing listens; a pre-start cleanup unit avoids false “Connection refused” on the VIP owner after reboot.

## Syncthing / Gitea

- Use Gitea for git push/pull; use Syncthing for deployed tree sync.
- Large initial tree: stop Syncthing, transfer a single archive **outside** the synced folder, extract, then start Syncthing.
- After cloning a VM, regenerate Syncthing identity before introducing it to the cluster.

## Related

- [architecture.md](architecture.md)
- [backup-and-restore.md](backup-and-restore.md)
- [failover.md](failover.md)
