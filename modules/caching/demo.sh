#!/usr/bin/env bash
# Caching strategies and invalidation (Redis). Cache-aside hit/miss and
# origin-offload demo.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile caching"
REDIS="$COMPOSE exec -T redis redis-cli"

echo "${BOLD}Cache-aside with Redis${RESET}"
note "Assumes 'make caching' is running (app + redis)."

hits() { curl -s "$GATEWAY/metrics" | awk -F'[ ]' '/cache_requests_total\{.*result="hit"/ {print $2}' | tail -1; }
misses() { curl -s "$GATEWAY/metrics" | awk -F'[ ]' '/cache_requests_total\{.*result="miss"/ {print $2}' | tail -1; }

step "Create a short link" "the write warms the cache (write-through of the new mapping)"
CODE=$(curl -s -X POST "$GATEWAY/shorten" -H 'Content-Type: application/json' -d '{"url":"https://example.com/cached"}' | sed -E 's/.*"code":"([^"]+)".*/\1/')
note "code = $CODE"
pause

step "First redirect" "served from cache because the write warmed it"
run "curl -s -o /dev/null -w 'status=%{http_code} time=%{time_total}s\n' $GATEWAY/$CODE"
note "hits=$(hits)  misses=$(misses)"
pause

step "Hammer the same code 50x" "all hits — the DB is not touched"
run "for i in \$(seq 1 50); do curl -s -o /dev/null $GATEWAY/$CODE; done; echo done"
note "hits=$(hits)  misses=$(misses)   <- hit count jumped by ~50"
pause

step "Inspect the cached key directly in Redis" "the value is the target URL"
run "$REDIS GET link:$CODE"
run "$REDIS TTL link:$CODE"
note "TTL counts down to expiry (CACHE_TTL, default 60s) — bounded staleness."
pause

step "Cold key = miss, then warm" "a code never read yet misses once, then caches"
COLD=$(curl -s -X POST "$GATEWAY/shorten" -H 'Content-Type: application/json' -d '{"url":"https://example.com/cold"}' | sed -E 's/.*"code":"([^"]+)".*/\1/')
run "$REDIS DEL link:$COLD >/dev/null; echo 'evicted to simulate a cold key'"
run "curl -s -o /dev/null $GATEWAY/$COLD; echo 'first read (miss -> populates)'"
run "curl -s -o /dev/null $GATEWAY/$COLD; echo 'second read (hit)'"
note "hits=$(hits)  misses=$(misses)"
pause

step "Redis stats — origin offload" "keyspace_hits dominate; the DB is spared"
run "$REDIS INFO stats | grep -E 'keyspace_hits|keyspace_misses'"

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
