#!/usr/bin/env bash
# Bootstraps postgres-replica as a streaming standby of postgres-primary.
# Used by the m2 profile. Runs as the container entrypoint before postgres starts.
#
# It performs a base backup from the primary (once), writes standby settings,
# then hands off to the standard postgres entrypoint in standby mode.
set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-postgres-primary}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPL_USER="${REPL_USER:-replicator}"
REPL_PASSWORD="${REPL_PASSWORD:-replicator}"
PGDATA="${PGDATA:-/var/lib/postgresql/data}"

export PGPASSWORD="$REPL_PASSWORD"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[replica] waiting for primary $PRIMARY_HOST:$PRIMARY_PORT ..."
  until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$REPL_USER"; do
    sleep 2
  done

  echo "[replica] taking base backup from primary ..."
  rm -rf "${PGDATA:?}"/*
  pg_basebackup \
    -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$REPL_USER" \
    -D "$PGDATA" -Fp -Xs -P -R \
    --slot=replica_slot

  echo "[replica] base backup complete; standby.signal written by -R."
  chmod 0700 "$PGDATA"
fi

echo "[replica] starting postgres in standby mode ..."
exec docker-entrypoint.sh postgres
