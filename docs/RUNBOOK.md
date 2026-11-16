# Runbook — operaciones básicas

Comandos y comprobaciones típicas. Ajusta nombres de host e IPs a tu lab.

## Keepalived / VIP

```bash
# Quién es MASTER
ip -br addr show eth0
sudo systemctl status keepalived
journalctl -u keepalived -f
```

Si la VIP no flota: revisa `vrrp_script`, firewall (protocolo VRRP / multicast) y que ambos nodos compartan `virtual_router_id` y autenticación.

## HAProxy

```bash
sudo systemctl reload haproxy
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock
curl -fsS https://10.10.0.10/health
```

## Galera

```bash
mysql -e "SHOW STATUS LIKE 'wsrep_%';"
# wsrep_cluster_size debe ser 3
# wsrep_local_state_comment = Synced
```

Arranque en frío (bootstrap del primer nodo): sigue la documentación de MariaDB para `galera_new_cluster`; no lo hagas en un cluster ya sano.

## WireGuard

```bash
sudo wg show
sudo systemctl status wg-quick@wg0
ping 10.20.0.1
```

## Proxmox

- Datacenter → HA: grupos y recursos críticos
- Comprobar quórum: `pvecm status`
- Backups: verificar último job en PBS / almacenamiento de backup

## Incidentes frecuentes

| Síntoma | Mirar primero |
| --- | --- |
| VIP no responde | Keepalived MASTER, `haproxy` local, firewall |
| App 5xx | Backends HAProxy, health checks, Galera Synced |
| Split-brain Galera | No arrancar dos nodos con bootstrap; recuperar desde el donante bueno |
| Sin acceso SSH | Peer WireGuard, rutas, `AllowedIPs` |
