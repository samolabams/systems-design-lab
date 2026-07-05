#!/usr/bin/env bash
# Measure the lab's actual latency numbers so estimates can be checked against reality.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"

echo "${BOLD}Measured latency numbers${RESET}"
note "Assumes 'make base' is running."
note "Learning loop: predict the rough order of magnitude, measure it, then compare with estimate.md."

step "End-to-end POST /shorten (gateway -> app -> database access layer -> primary database)"
predict "Should this end-to-end request be closer to milliseconds, hundreds of milliseconds, or seconds on a local lab?" \
	"Usually milliseconds locally; a much larger number means something else is happening."
run "for i in 1 2 3; do curl -s -o /dev/null -w 'shorten: %{time_total}s\n' -X POST $GATEWAY/shorten -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}'; done"
checkpoint "What does end-to-end time include that a database-only measurement does not?" \
	   "Gateway, app code, pooling, database work, serialization, and network hops."

step "Database indexed point read (inside the DB, no network)"
predict "Should an indexed point read be a reason to shard at this lab scale?" \
	"No. If it is already very fast, sharding would add complexity before solving a measured limit."
run "$COMPOSE exec -T postgres-primary psql -U app -d app -c '\\timing on' -c \"SELECT count(*) FROM links;\" | grep -i time || true"
checkpoint "Why measure inside the database separately?" \
	   "It separates database execution time from application and network overhead."

step "Cross-container round trip (gateway -> app)"
predict "Should a same-host container hop look like a cross-region network hop?" \
	"No. Same-host container RTT should be tiny compared with cross-region latency."
run "$COMPOSE exec -T gateway sh -c 'time wget -qO- http://app:3000/health >/dev/null' 2>&1 | grep real || true"
checkpoint "What design choice changes when the hop becomes cross-region?" \
	   "Synchronous cross-region calls become expensive; replication, locality, and async workflows matter more."

note "Compare these values against the table in estimate.md. Measured values are more reliable than generic latency tables."
echo
note "${BOLD}Done.${RESET} Cleanup: make reset"
