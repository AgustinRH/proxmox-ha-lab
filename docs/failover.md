# Failover — behaviour and how to test it

This describes the **intended** behaviour of the three-site design. Adjust names/IPs to your lab. Do not force quorum or bootstrap Galera on two sides of a partition.

## Layers that can fail independently

| Layer | Healthy signal | Failover owner |
| --- | --- | --- |
| Proxmox / Corosync | `pvecm status` → Quorate | Cluster votes (+ optional last-man helper) |
| Keepalived VIP | VIP present on one app VM; HAProxy up | VRRP priority + health script |
| HAProxy | Backend checks green | Removes bad backends |
| Galera | `Primary` + `Synced`, size = member count | Quorum; optional last-man **only** with gateway check |
| WireGuard | `wg show`, inter-site pings | Routing / peer endpoints |

## Scenario A — one Proxmox node down

### What should happen

1. Corosync loses one vote. With three nodes, two remain → still quorate (need >50%).
2. Guests on the dead node are offline. They do **not** migrate unless you configured HA for those VMIDs.
3. If the VIP lived on an app VM of that node, Keepalived on the next priority takes the VIP (seconds).
4. Galera member count drops by the VMs on that node. Remaining members stay `Primary` if majority of the configured ring is still up.
5. PBS on that node is unreachable; other nodes’ backup jobs continue.

### How to test (maintenance window)

1. Confirm baseline: `pvecm status`, VIP ping, app HTTP 200, Galera size/status on two app VMs.
2. Gracefully shut down **one** Proxmox node (or `systemctl poweroff` after migrating nothing — this test is about loss).
3. Within ~30s: cluster still quorate; VIP reachable; HTTP OK; Galera `Primary` on survivors.
4. Power the node back; wait for Corosync rejoin; start guests if `onboot` is set; confirm Galera nodes return to `Synced` without `galera_new_cluster`.

## Scenario B — one entire site down

### What should happen

1. Same as losing that site’s Proxmox vote(s) and all of its VMs.
2. VIP `10.99.0.10/32` moves via Keepalived unicast VRRP (example priority chain: site A → B → C). Point the cross-site host route for that `/32` at the new owner (**TODO** automation).
3. Galera remains writable if remaining members > half of total members.
4. Syncthing/Gitea peers at the live sites keep serving; the down site resyncs on return.

### How to test

1. Prefer simulating **network isolation** of the site (firewall drop / unplug WAN+overlay) before pulling power, so you can observe minority behaviour safely.
2. From a client on a live site: VIP and app still work.
3. On the isolated site: confirm it does **not** open a second Galera primary (gateway check should block last-man if the site cannot reach the shared gateway design you use — if each site has only a local gateway, revisit the helper logic before enabling it).
4. Restore connectivity; members should join the existing Primary.

## Scenario C — network split (two sites vs one, or 50/50 with even votes)

### What should happen

- The side with **majority** Proxmox votes stays quorate and may keep the VIP if its Keepalived nodes still run.
- The minority side must not run `pvecm expected …` permanently or `galera_new_cluster`.
- If you deploy a “last man” service, it must require: no quorum for N seconds **and** reachability to a designated gateway **and** being first in a documented priority chain. A node with the cable unplugged must fail the gateway check.

### How to test

1. Split WireGuard / routing so site C cannot reach A+B (or unplug overlay only).
2. Watch: A+B remain Primary; C’s Galera goes non-Primary; C must not bootstrap.
3. Heal the overlay; C joins; full size restored.

## Useful checks

On a Proxmox node:

```bash
pvecm status
qm list
```

On an app VM:

```bash
ip -br addr show | grep 10.99.0.10   # floating VIP example
systemctl is-active haproxy keepalived mariadb
mysql --batch --skip-column-names -e \
  "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_status','wsrep_local_state_comment','wsrep_cluster_size');"
```

Healthy Galera line: `Primary` / `Synced` / expected size.

## Cold start of the whole fleet

If **all** sites power off together, Galera may come up with no Primary. Do **not** run `galera_new_cluster` on two VMs. Procedure sketch:

1. Stop any last-man timers.
2. Stop MariaDB everywhere; recover positions (`galera_recovery` / `grastate.dat`).
3. Bootstrap **once** from the highest safe seqno.
4. Start others as joiners one by one.
5. Re-enable helpers only when size and status look right.

Full command sheets stay in your private runbooks (they contain environment-specific paths). Public summary only — **TODO:** link internal ticket/doc ID if allowed.
