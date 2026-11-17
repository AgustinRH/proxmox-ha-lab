#!/usr/bin/env bash
# notify-vip-wg.sh — Keepalived notify_* helper
#
# EXAMPLE: when this app VM becomes VRRP MASTER, move VIP 10.99.0.10/32 into
# WireGuard AllowedIPs on every site gateway and install a matching host route.
# On BACKUP / FAULT, withdraw the /32 from this site's peer AllowedIPs.
#
# Why a plain `ip route` is not enough
# ------------------------------------
# WireGuard uses cryptokey routing. An address is encrypted toward a peer only
# if that address is covered by the peer's AllowedIPs. A kernel host route
# without AllowedIPs still leaves WG dropping the /32 for that peer.
#
# Install
# -------
#   install -m 0750 -o root -g keepalived_script \
#     notify-vip-wg.sh /etc/keepalived/notify-vip-wg.sh
#   # env file — not world-readable, but MUST be readable by keepalived_script:
#   /etc/keepalived/notify-vip-wg.env   (e.g. mode 640, group keepalived_script)
#
# Privilege note (enable_script_security)
# ---------------------------------------
# notify_* runs as script_user keepalived_script, not root. That user must be
# able to read the env file and SSH to the site routers (dedicated key in
# ~keepalived_script/.ssh, authorized on GATEWAYS / LOCAL_ROUTER_SSH).
#
# Keepalived invokes: notify_* <type> <name> <state> <priority>
# We key off $3 (MASTER | BACKUP | FAULT).
#
# Do not put 10.99.0.10/32 in the static wg0-site-*.conf AllowedIPs lists.

set -euo pipefail

STATE="${3:-unknown}"
CONF="${NOTIFY_VIP_ENV:-/etc/keepalived/notify-vip-wg.env}"

# Defaults (overridden by env file) — example addresses only
WG_IF="${WG_IF:-wg0}"
VIP_HOST="${VIP_HOST:-10.99.0.10}"
VIP="${VIP:-${VIP_HOST}/32}"
LOCAL_SITE="${LOCAL_SITE:-a}"          # a | b | c  (this webdb's site)
LOCAL_WEBDB="${LOCAL_WEBDB:-10.10.40.21}"  # this VM on services VLAN

PEER_A_PUBKEY="${PEER_A_PUBKEY:-<PUBLIC_KEY_A>}"
PEER_B_PUBKEY="${PEER_B_PUBKEY:-<PUBLIC_KEY_B>}"
PEER_C_PUBKEY="${PEER_C_PUBKEY:-<PUBLIC_KEY_C>}"
PEER_A_WG="${PEER_A_WG:-10.255.50.1}"
PEER_B_WG="${PEER_B_WG:-10.255.50.2}"
PEER_C_WG="${PEER_C_WG:-10.255.50.3}"
PEER_A_BASE="${PEER_A_BASE:-10.10.10.0/24,10.10.20.0/24,10.10.30.0/24,10.10.40.0/24}"
PEER_B_BASE="${PEER_B_BASE:-10.20.10.0/24,10.20.20.0/24,10.20.30.0/24,10.20.40.0/24}"
PEER_C_BASE="${PEER_C_BASE:-10.30.10.0/24,10.30.20.0/24,10.30.30.0/24,10.30.40.0/24}"

# Remote site WireGuard routers only (not this site). Example on webdb-a1:
#   GATEWAYS="root@10.20.10.1 root@10.30.10.1"
# Those hosts get: wg set AllowedIPs += VIP on our peer, and
#   ip route replace VIP via our WG address.
GATEWAYS="${GATEWAYS:-}"

# This site's router — host route VIP → LOCAL_WEBDB (services VLAN), not via WG
LOCAL_ROUTER_SSH="${LOCAL_ROUTER_SSH:-}"

if [[ -f "$CONF" ]]; then
  # shellcheck source=/dev/null
  source "$CONF"
fi

log() { logger -t keepalived-vip-wg -- "$*" 2>/dev/null || printf '%s\n' "$*" >&2; }

pubkey_for() {
  case "$1" in
    a) printf '%s' "$PEER_A_PUBKEY" ;;
    b) printf '%s' "$PEER_B_PUBKEY" ;;
    c) printf '%s' "$PEER_C_PUBKEY" ;;
    *) return 1 ;;
  esac
}

wg_addr_for() {
  case "$1" in
    a) printf '%s' "$PEER_A_WG" ;;
    b) printf '%s' "$PEER_B_WG" ;;
    c) printf '%s' "$PEER_C_WG" ;;
  esac
}

base_for() {
  case "$1" in
    a) printf '%s' "$PEER_A_BASE" ;;
    b) printf '%s' "$PEER_B_BASE" ;;
    c) printf '%s' "$PEER_C_BASE" ;;
  esac
}

# Build AllowedIPs string: site prefixes, optionally + VIP for the owner peer
allowed_ips_for() {
  local site="$1" with_vip="$2"
  local base
  base="$(base_for "$site")"
  # Always include the peer's WG /32 so the overlay itself stays reachable
  local wg32
  wg32="$(wg_addr_for "$site")/32"
  if [[ "$with_vip" == "1" ]]; then
    printf '%s,%s,%s' "$wg32" "$base" "$VIP"
  else
    printf '%s,%s' "$wg32" "$base"
  fi
}

# Run a command on a gateway (local if empty host / "local")
gw_run() {
  local host="$1"
  shift
  if [[ -z "$host" || "$host" == "local" ]]; then
    "$@"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" "$@"
  fi
}

# True if $WG_IF already has this public key as a peer (avoids creating orphans)
peer_exists_on_gw() {
  local gw="$1"
  local pub="$2"
  gw_run "$gw" wg show "$WG_IF" peers 2>/dev/null | grep -qxF "$pub"
}

set_peer_allowed_on_gw() {
  local gw="$1"
  local site="$2"
  local with_vip="$3"
  local pub ips
  pub="$(pubkey_for "$site")"
  if ! peer_exists_on_gw "$gw" "$pub"; then
    # Expected on the owner's own gateway (no self-peer)
    return 0
  fi
  ips="$(allowed_ips_for "$site" "$with_vip")"
  gw_run "$gw" wg set "$WG_IF" peer "$pub" allowed-ips "$ips"
}

# advertise: owner peer → base+VIP; other existing peers → base only; host route via owner WG
apply_advertise_on_gateway() {
  local gw="$1"
  local owner="$2"
  local s with
  for s in a b c; do
    with=0
    [[ "$s" == "$owner" ]] && with=1
    set_peer_allowed_on_gw "$gw" "$s" "$with"
  done
  # On remote gateways, send VIP traffic into the tunnel toward the owner
  gw_run "$gw" ip route replace "${VIP_HOST}/32" via "$(wg_addr_for "$owner")" dev "$WG_IF" 2>/dev/null \
    || gw_run "$gw" ip route replace "${VIP_HOST}/32" dev "$WG_IF"
}

# withdraw: strip VIP from this site's peer only (late BACKUP must not undo new MASTER)
apply_withdraw_site_on_gateway() {
  local gw="$1"
  local site="$2"
  set_peer_allowed_on_gw "$gw" "$site" 0
}

# Local site: clients use the site router; point VIP at the winning webdb
apply_local_vip_route() {
  local action="$1"  # add | del
  local route_line
  if [[ -z "$LOCAL_ROUTER_SSH" ]]; then
    log "LOCAL_ROUTER_SSH unset — skip local VIP route (set it in ${CONF})"
    return 0
  fi
  if [[ "$action" == "add" ]]; then
    gw_run "$LOCAL_ROUTER_SSH" ip route replace "${VIP_HOST}/32" via "$LOCAL_WEBDB"
    return 0
  fi
  # Withdraw: only delete if nexthop is still LOCAL_WEBDB. A late BACKUP/FAULT
  # must not race the new MASTER, which may already have replaced this route
  # (via GATEWAYS) with via <other-site-wg> — deleting that black-holes the VIP.
  route_line="$(gw_run "$LOCAL_ROUTER_SSH" ip route show "${VIP_HOST}/32" 2>/dev/null || true)"
  if [[ "$route_line" == *" via ${LOCAL_WEBDB} "* || "$route_line" == *" via ${LOCAL_WEBDB}" ]]; then
    gw_run "$LOCAL_ROUTER_SSH" ip route del "${VIP_HOST}/32" 2>/dev/null || true
  else
    log "skip local VIP route del (nexthop is not ${LOCAL_WEBDB}: ${route_line:-none})"
  fi
}

advertise() {
  local gw
  log "MASTER: advertising ${VIP} via site=${LOCAL_SITE} peer=$(wg_addr_for "$LOCAL_SITE")"
  if [[ -z "$GATEWAYS" ]]; then
    log "GATEWAYS unset — example local apply only on this host if it is the WG endpoint"
    apply_advertise_on_gateway "local" "$LOCAL_SITE"
  else
    for gw in $GATEWAYS; do
      apply_advertise_on_gateway "$gw" "$LOCAL_SITE" || log "warn: gateway ${gw} update failed"
    done
  fi
  apply_local_vip_route add
}

withdraw() {
  local gw
  # Only strip VIP from OUR peer. Never wipe other peers' AllowedIPs — a late
  # BACKUP notify must not undo the new MASTER's advertise.
  log "BACKUP/FAULT: withdrawing ${VIP} from site=${LOCAL_SITE} AllowedIPs only"
  if [[ -z "$GATEWAYS" ]]; then
    apply_withdraw_site_on_gateway "local" "$LOCAL_SITE"
  else
    for gw in $GATEWAYS; do
      apply_withdraw_site_on_gateway "$gw" "$LOCAL_SITE" || log "warn: gateway ${gw} withdraw failed"
    done
  fi
  apply_local_vip_route del
}

case "$STATE" in
  MASTER|master) advertise ;;
  BACKUP|backup|FAULT|fault) withdraw ;;
  *) log "ignore state=${STATE}" ;;
esac

exit 0
