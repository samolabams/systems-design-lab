#!/usr/bin/env bash
# Leader election & replica sets. Kill the primary and watch
# the survivors elect a new one with no operator action.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile leader-election-replica-sets"
# Run mongosh from inside mongo2 so it still works after we kill mongo1. The
# replica-set URI lets the driver discover the current PRIMARY and route writes
# there automatically — even after a failover changes who the primary is.
RS_URI="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0"
MSH="$COMPOSE exec -T mongo2 mongosh --quiet \"$RS_URI\""
# Topology queries can run against any member (read from the local node).
MSH_LOCAL="$COMPOSE exec -T mongo2 mongosh --quiet"

echo "${BOLD}Leader election & replica sets${RESET}"
note "Assumes 'make leader-election-replica-sets' is running (MongoDB lab: mongo1/2/3 + mongo-init)."

primary() { eval "$MSH_LOCAL --eval 'db.hello().primary'" 2>/dev/null | tr -d '[:space:]'; }

step "Show the current topology" "one PRIMARY, two SECONDARY"
run "$MSH_LOCAL --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'"
note "primary = $(primary)"
pause

step "Write a document with majority durability" "the driver routes it to the PRIMARY; survives failover"
run "$MSH --eval 'db.getSiblingDB(\"lab\").notes.insertOne({ msg: \"before failover\", at: new Date() }, { writeConcern: { w: \"majority\" } })'"
pause

step "Kill the primary" "mongo1 disappears; the set loses its leader"
run "$COMPOSE kill mongo1"
note "election in progress — waiting for a NEW primary (no operator action) ..."
NEW=""
for i in $(seq 1 30); do
  NEW="$(primary)"
  if [ -n "$NEW" ] && [[ "$NEW" != *mongo1* ]]; then break; fi
  sleep 2
done
note "new primary = ${NEW:-<none yet>}"
pause

step "Read the document from the new primary" "data is intact after automatic failover"
run "$MSH --eval 'db.getSiblingDB(\"lab\").notes.find().toArray()'"
pause

step "Quorum check: kill a second node" "lone survivor steps DOWN — no majority, no writes (CP)"
run "$COMPOSE kill mongo3 || true"
note "waiting for the step-down (a primary that loses majority demotes itself within ~electionTimeout) ..."
sleep 14
run "$MSH_LOCAL --eval 'db.hello().ismaster' || true"
note "With only 1 of 3 reachable there is no majority, so it refuses to be primary."
pause

step "Heal the cluster" "restart the killed nodes; they rejoin as SECONDARY and catch up"
run "$COMPOSE up -d mongo1 mongo3"
sleep 8
run "$MSH_LOCAL --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))' || true"

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
