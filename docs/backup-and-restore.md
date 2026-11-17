# Backup and restore — Proxmox Backup Server

## Layout

| Proxmox node | PBS guest (example) | Datastore name (example) | Holds backups of |
| --- | --- | --- | --- |
| `pve-a` | `pbs-a` | `backup` on that PBS | App VMs on `pve-a` only |
| `pve-b` | `pbs-b` | `backup` | App VMs on `pve-b` |
| `pve-c` | `pbs-c` | `backup` | App VMs on `pve-c` |

Each node registers a storage entry such as `pbs-a` pointing at its local PBS. **Do not** expect one backup job to write to foreign PBS instances that only exist on other nodes.

PBS UI (example): `https://10.10.30.21:8007` — user `<CHANGE_ME>`.

## Schedule (template)

Align with production habits; fill exact cron from your UI:

| Job | Node | VMs included | Mode | Interval |
| --- | --- | --- | --- | --- |
| `webs-a` | `pve-a` | `webdb-a1` (+ optional `webdb-a2`) | snapshot | **TODO** (cron / PBS schedule) |
| `webs-b` | `pve-b` | `webdb-b1` (+ optional `webdb-b2`) | snapshot | **TODO** |
| `webs-c` | `pve-c` | `webdb-c1` (+ optional `webdb-c2`) | snapshot | **TODO** |

Usually **exclude** PBS VMs and monitoring VMs from these jobs unless you have a separate policy.

Retention: **TODO** (e.g. keep N daily / N weekly — copy from PBS datastore prune settings).

## What these backups protect

- Full VM disks (OS + app + local MariaDB datadir as it was at snapshot time).
- Fast rollback of a single site’s app VMs after operator error or disk failure.

What they are **not**:

- A substitute for Galera’s running replicas (use both).
- Cross-site continuous replication unless you add PBS sync/remote — **TODO** if you enable it.

## Restore test procedure (do this on a schedule)

Goal: prove a backup boots, not only that the job is green.

1. **Pick** a recent successful snapshot of one app VM (e.g. `webdb-b1`) from its local PBS.
2. **Restore** to a **new** VMID on a healthy node (or the same node if space allows). Do not overwrite production on the first test.
3. **Detach** the test VM from production networks if needed (use a lab bridge) so it cannot join Galera or steal the VIP:
   - Do not start Keepalived/HAProxy against the live VIP.
   - Do not start Syncthing with production device IDs without renaming.
   - Prefer stopping Galera/`wsrep` or isolating NIC before first boot on a shared VLAN.
4. **Boot** the restored VM; verify console login and that disk content looks right (app files, mysql datadir present).
5. **Optional deeper check:** start MariaDB in bootstrap-isolated mode or restore a logical dump extracted offline — **TODO** document your preferred deep check.
6. **Record** date, VMID, snapshot ID, result, and destroy the test VM.
7. **Cadence:** at least quarterly, and after any PBS or Proxmox major upgrade.

## Emergency restore of a production VM

1. Confirm the node has quorum and free space.
2. Stop the broken VM if it is still registered.
3. Restore from PBS into the **same** VMID only if you accept overwrite; otherwise restore aside and cut over DNS/VIP after validation.
4. If the VM is a Galera member, bring it up as a **joiner** to the existing Primary — never `galera_new_cluster` while another Primary exists.
5. Re-check ProxySQL, HAProxy backend, Syncthing device ID uniqueness.

## Monitoring hooks

Alert when:

- PBS job fails or misses two consecutive windows.
- Datastore free space below **TODO** %.
- PBS guest or service down.

## Related

- [failover.md](failover.md) — when a site is gone, only other sites’ PBS remain.
- [runbook.md](runbook.md) — upgrades that should be preceded by a fresh backup.
