#!/usr/bin/env bash
# check-galera.sh — report Galera cluster size, status and local sync state
# Run on any MariaDB Galera member (needs mysql client + credentials).
#
# Usage:
#   ./check-galera.sh
#   MYSQL_USER=monitoring MYSQL_PASSWORD='<CHANGE_ME>' ./check-galera.sh
#
# Exit codes:
#   0 = Primary + Synced (and size >= MIN_SIZE if set)
#   1 = query failed or not healthy
#   2 = usage / dependency error

set -euo pipefail

MYSQL_USER="${MYSQL_USER:-root}"
# Prefer socket as root via sudo; password auth for monitoring users
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
# Optional: fail if cluster smaller than this (e.g. 3)
MIN_SIZE="${MIN_SIZE:-0}"

if ! command -v mysql >/dev/null 2>&1; then
  echo "error: mysql client not found" >&2
  exit 2
fi

mysql_cmd=(mysql --batch --skip-column-names)
if [[ -n "$MYSQL_PASSWORD" ]]; then
  mysql_cmd+=(-h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD")
else
  # Socket / auth_socket style (often: sudo ./check-galera.sh)
  mysql_cmd+=(-u "$MYSQL_USER")
fi

query() {
  local var="$1"
  "${mysql_cmd[@]}" -e "SHOW STATUS LIKE '${var}';" | awk '{print $2}'
}

status="$(query wsrep_cluster_status || true)"
state="$(query wsrep_local_state_comment || true)"
size="$(query wsrep_cluster_size || true)"
ready="$(query wsrep_ready || true)"
uuid="$(query wsrep_cluster_state_uuid || true)"

if [[ -z "$status" && -z "$state" ]]; then
  echo "error: could not query wsrep status (mysqld down or auth failed)" >&2
  exit 1
fi

echo "wsrep_cluster_status      = ${status:-?}"
echo "wsrep_local_state_comment = ${state:-?}"
echo "wsrep_cluster_size        = ${size:-?}"
echo "wsrep_ready               = ${ready:-?}"
echo "wsrep_cluster_state_uuid  = ${uuid:-?}"

# Human one-liner
if [[ "$status" == "Primary" && "$state" == "Synced" && "$ready" == "ON" ]]; then
  echo "summary: HEALTHY (Primary/Synced)"
  healthy=1
else
  echo "summary: UNHEALTHY (want Primary + Synced + ready=ON)"
  healthy=0
fi

if [[ "$MIN_SIZE" =~ ^[0-9]+$ ]] && [[ "$MIN_SIZE" -gt 0 ]]; then
  if [[ "${size:-0}" -lt "$MIN_SIZE" ]]; then
    echo "summary: size ${size:-0} < MIN_SIZE ${MIN_SIZE}"
    healthy=0
  fi
fi

# Portfolio expected size for the 3-node example ring
echo "hint: example ring is 10.10.40.21, .31, .41 (size 3 when complete)"

[[ "$healthy" -eq 1 ]]
