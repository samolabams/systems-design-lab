#!/usr/bin/env bash
# €” Multi-region, DR & backups. Backup -> destroy -> restore drill that
# proves "replication is not a backup" and measures the achieved RPO/RTO. Pausable.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile replication-failover"
PRIMARY="$COMPOSE exec -T postgres-primary"
REPLICA="$COMPOSE exec -T postgres-replica"
BACKUP="/tmp/sdl-dr-backup.sql"

echo "${BOLD}€” Disaster recovery: replication â‰  backup${RESET}"
note "Assumes 'make replication-failover' is running (primary + streaming standby)."

count() { $1 psql -U app -d app -tAc 'SELECT count(*) FROM links;' 2>/dev/null | tr -d '[:space:]'; }

step "Seed some rows on the primary" "they replicate to the standby in a moment"
run "for i in \$(seq 1 5); do curl -s -X POST $GATEWAY/shorten -H 'Content-Type: application/json' -d \"{\\\"url\\\":\\\"https://example.com/\$i\\\"}\" >/dev/null; done; echo seeded"
sleep 1
note "primary rows:  $(count "$PRIMARY")"
note "replica rows:  $(count "$REPLICA")   (replication caught up)"
pause

step "Take an out-of-band backup (your real safety net)" "this copy lives outside replication"
t0=$(date +%s.%N)
run "$PRIMARY pg_dump -U app --data-only -t links app > $BACKUP"
t1=$(date +%s.%N)
note "backup written to $BACKUP in $(printf '%.2f' "$(echo "$t1 - $t0" | bc)")s"
pause

step "Disaster: a careless DELETE on the primary" "watch it replicate INSTANTLY to the standby"
run "$PRIMARY psql -U app -d app -c 'DELETE FROM links;'"
sleep 1
note "primary rows:  $(count "$PRIMARY")"
note "replica rows:  $(count "$REPLICA")   ${YELLOW}<- the standby is empty too!${RESET}"
note "Availability machinery (the replica) did NOT protect the data â€” the bad write replicated."
pause

step "Recover from the backup (the only thing that can save you)" "rows return from the out-of-band copy"
t0=$(date +%s.%N)
run "$PRIMARY psql -U app -d app < $BACKUP"
t1=$(date +%s.%N)
rto=$(printf '%.2f' "$(echo "$t1 - $t0" | bc)")
sleep 1
note "primary rows:  $(count "$PRIMARY")   (restored)"
note "replica rows:  $(count "$REPLICA")   (restore replicated forward)"
pause

step "Report the numbers" "RPO and RTO are measured, not aspirational"
note "RTO (this restore):  ${rto}s  â€” how long recovery took."
note "RPO (your exposure): everything written AFTER the backup and BEFORE the disaster."
note "Shrink RPO with more frequent backups / WAL archiving (PITR); shrink RTO with"
note "warm standbys and rehearsed runbooks. Both are trade-offs against cost."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}  (backup left at $BACKUP)"
