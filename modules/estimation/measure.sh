#!/usr/bin/env bash
# €” measure the lab's ACTUAL latency numbers so estimates can be
# checked against reality. Reuses the base system.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"

echo "${BOLD}€” measured latency numbers${RESET}"
note "Assumes 'make base' is running."

step "End-to-end POST /shorten (gateway â†’ app â†’ pgbouncer â†’ primary)"
run "for i in 1 2 3; do curl -s -o /dev/null -w 'shorten: %{time_total}s\n' -X POST $GATEWAY/shorten -H 'Content-Type: application/json' -d '{\"url\":\"https://example.com\"}'; done"

step "Postgres indexed point read (inside the DB, no network)"
run "$COMPOSE exec -T postgres-primary psql -U app -d app -c '\\timing on' -c \"SELECT count(*) FROM links;\" | grep -i time || true"

step "Cross-container round trip (gateway â†’ app)"
run "$COMPOSE exec -T gateway sh -c 'time wget -qO- http://app:3000/health >/dev/null' 2>&1 | grep real || true"

note "Compare these against the table in estimate.md. Real numbers beat folklore."
echo "${BOLD}Done.${RESET}"
