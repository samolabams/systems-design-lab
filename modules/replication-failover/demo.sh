#!/usr/bin/env bash
# Replication, lag, read-after-write, indexing, failover. Pausable.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"
PRIMARY="$COMPOSE exec -T postgres-primary psql -U app -d app -t -A"
REPLICA="$COMPOSE exec -T postgres-replica psql -U app -d app -t -A"

wait_for_sql() {
	local name="$1" cmd="$2" deadline=$((SECONDS + 30))
	until eval "$cmd -c 'SELECT 1;'" >/dev/null 2>&1; do
		if [ "$SECONDS" -ge "$deadline" ]; then
			echo "Timed out waiting for $name. Run 'make replication-failover' and wait for containers to become healthy." >&2
			exit 1
		fi
		sleep 2
	done
}

echo "${BOLD}Postgres replication & failover${RESET}"
note "Assumes 'make replication-failover' is running (primary + streaming replica)."

wait_for_sql "postgres-primary" "$PRIMARY"
wait_for_sql "postgres-replica" "$REPLICA"

step "Confirm the replica is in recovery (read-only standby)" "expect 't'"
run "$REPLICA -c 'SELECT pg_is_in_recovery();'"
pause

step "Write on the primary, read on the replica" "the row appears on both"
run "$PRIMARY -c \"INSERT INTO links(code,url) VALUES('demo123','https://example.com/m2') ON CONFLICT (code) DO NOTHING;\""
note "Reading from the replica:"
run "$REPLICA -c \"SELECT code,url FROM links WHERE code='demo123';\""
pause

step "Inspect replication lag" "lag in bytes; grows under write load"
run "$PRIMARY -c \"SELECT client_addr, state, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes FROM pg_stat_replication;\""
pause

step "Read-after-write hazard" "pause replay so the stale-read window is visible"
note "Local replication is often too fast to catch by luck, so this step pauses WAL replay on the replica."
note "That creates the same kind of stale-read window a lagging replica can create under load or network delay."
run "$REPLICA -c 'SELECT pg_wal_replay_pause();'"
run "$PRIMARY -c \"INSERT INTO links(code,url) VALUES('fresh01','https://example.com/fresh') ON CONFLICT (code) DO UPDATE SET url = EXCLUDED.url;\""
run "$REPLICA -c \"SELECT count(*) AS visible_on_replica_while_replay_is_paused FROM links WHERE code='fresh01';\""
run "$REPLICA -c 'SELECT pg_wal_replay_resume();'"
run "for i in \$(seq 1 10); do visible=\$($REPLICA -c \"SELECT count(*) FROM links WHERE code='fresh01';\"); [ \"\$visible\" = \"1\" ] && { echo visible_after_replay_resume=1; break; }; sleep 1; done"
note "The first count should be 0 while replay is paused, then 1 after replay resumes."
pause

step "Indexing aside: slow query plan BEFORE an index" "expect a Seq Scan"
note "This is a short reminder: fix local query shape before adding distributed architecture."
run "$PRIMARY -c \"EXPLAIN ANALYZE SELECT * FROM links WHERE url LIKE 'https://example.com/m2';\""
pause

step "Add a B-tree index and re-plan" "expect an Index/Bitmap Scan"
run "$PRIMARY -c \"CREATE INDEX IF NOT EXISTS idx_links_url ON links(url);\""
run "$PRIMARY -c \"EXPLAIN ANALYZE SELECT * FROM links WHERE url = 'https://example.com/m2';\""
pause

step "Failover drill — promote the replica" "replica becomes primary (recovery=f)"
note "In production you'd kill the primary first; here we just promote."
run "$COMPOSE exec -T postgres-replica pg_ctl promote -D /var/lib/postgresql/data || $REPLICA -c 'SELECT pg_promote();'"
run "$REPLICA -c 'SELECT pg_is_in_recovery();'"
note "Now repoint the app's DATABASE_URL at the promoted node."

echo "${BOLD}Done.${RESET}"
