#!/usr/bin/env bash
# Initialize a 3-node MongoDB replica set (rs0).
# Run once by the `mongo-init` one-shot container. Waits for mongo1 to accept
# connections, then configures the replica set with all three members. Mongo's
# nodes then hold a Raft-like election and choose a primary automatically — the
# contrast with Postgres's manual pg_promote() failover (replication and failover).
set -euo pipefail

echo "[mongo-init] waiting for mongo1 ..."
until mongosh --host mongo1:27017 --quiet --eval 'db.runCommand({ ping: 1 }).ok' >/dev/null 2>&1; do
  sleep 2
done

# If the set is already configured (container restart), do nothing.
if mongosh --host mongo1:27017 --quiet --eval 'rs.status().ok' >/dev/null 2>&1; then
  echo "[mongo-init] replica set already initialized; nothing to do."
  exit 0
fi

echo "[mongo-init] initiating replica set rs0 ..."
mongosh --host mongo1:27017 --quiet --eval '
  rs.initiate({
    _id: "rs0",
    members: [
      { _id: 0, host: "mongo1:27017", priority: 2 },
      { _id: 1, host: "mongo2:27017", priority: 1 },
      { _id: 2, host: "mongo3:27017", priority: 1 }
    ]
  });
'

echo "[mongo-init] waiting for a primary to be elected ..."
until mongosh --host mongo1:27017 --quiet --eval 'db.hello().primary' 2>/dev/null | grep -q ':27017'; do
  sleep 2
done

echo "[mongo-init] replica set rs0 is up. Primary:"
primary=$(mongosh --host mongo1:27017 --quiet --eval 'db.hello().primary' 2>/dev/null || true)
echo "${primary:-primary elected; final lookup skipped}"
