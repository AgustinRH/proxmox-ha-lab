# Arquitectura del laboratorio Proxmox HA

## Objetivos

1. **Disponibilidad:** un nodo Proxmox o un balanceador puede caer sin cortar el servicio.
2. **Consistencia de datos:** MariaDB Galera con quorum de 3 nodos.
3. **Operación remota segura:** administración solo vía WireGuard (sin exponer SSH/Proxmox UI a Internet).
4. **Reproducibilidad:** configs versionadas con placeholders, no con secretos de producción.

## Capas

### 1. Compute — Proxmox VE cluster

- Tres nodos (`pve1`, `pve2`, `pve3`) en el mismo cluster.
- Corosync para quorum (idealmente red dedicada o VLAN de cluster).
- Almacenamiento: ZFS local + réplica, o Ceph si el lab lo permite; PBS para backups.
- VMs/CTs etiquetadas por rol (`lb`, `db`, `app`, `vpn`).

### 2. Edge — Keepalived + HAProxy

- Dos VMs activas/pasivas (o activas/activas con cuidado).
- **Keepalived** anuncia una **VIP** (`10.10.0.10` en el ejemplo) con VRRP.
- Health check: si HAProxy local no responde, cede el MASTER.
- **HAProxy** termina TLS (o pasa TCP) y reparte a backends de aplicación / Galera (puerto de lectura o proxy SQL según diseño).

### 3. Datos — MariaDB Galera

- Tres nodos multi-master.
- SST con `mariabackup` (recomendado) o `rsync`.
- Aplicaciones escriben preferentemente a un escritor “primario lógico” vía HAProxy, o usan un proxy SQL (ProxySQL/MaxScale) en un diseño más avanzado.
- Backups lógicos periódicos + snapshots de disco.

### 4. Acceso — WireGuard

- Gateway con interfaz `wg0` y red overlay `10.20.0.0/24`.
- Peers de operadores; split-tunnel hacia redes de mgmt/cluster.
- La UI de Proxmox (`8006`) y SSH quedan en redes no enrutadas desde Internet.

## Direccionamiento de ejemplo (RFC1918)

| Red | CIDR | Uso |
| --- | --- | --- |
| Public / DMZ | `203.0.113.0/24` (TEST-NET) | Solo VIP publicada o 1:1 NAT de lab |
| Edge / VIP | `10.10.0.0/24` | HAProxy, VIP |
| Cluster / Corosync | `10.10.10.0/24` | Tráfico de cluster Proxmox |
| Storage | `10.10.20.0/24` | Réplica / Ceph / backups |
| Galera | `10.10.30.0/24` | Nodos DB |
| WireGuard | `10.20.0.0/24` | Operadores |

Sustituye siempre por tu plan de IP real **fuera de git**.

## Flujo de una petición

1. Cliente → VIP (`10.10.0.10`) en el nodo Keepalived MASTER.
2. HAProxy elige backend sano (checks HTTP `/health` o TCP).
3. App habla con Galera (o a través del mismo HAProxy en puerto SQL).
4. Si cae el MASTER de Keepalived, el BACKUP asume la VIP en segundos.

## Fallos que el diseño cubre

| Fallo | Efecto esperado |
| --- | --- |
| Caída de 1 nodo Proxmox | VMs migran / reinician según HA; quorum se mantiene |
| Caída de 1 HAProxy | Keepalived mueve VIP al peer |
| Caída de 1 Galera | Cluster sigue con 2/3; regenerar nodo antes de otro fallo |
| Pérdida de enlace WAN | Operación vía WireGuard desde otra salida, si el peer tiene ruta |

## Qué no incluye (a propósito)

- Credenciales, IPs públicas reales ni nombres de dominio de producción
- Automatización completa (Ansible/Terraform): se puede añadir en una fase 2
- Observabilidad (Prometheus/Grafana): recomendable, no bloqueante para el lab base

Ver operación diaria en [RUNBOOK.md](RUNBOOK.md).
