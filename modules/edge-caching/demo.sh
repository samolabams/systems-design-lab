#!/usr/bin/env bash
# €” Edge / CDN caching. An Nginx edge cache sits in front of the
# gateway and answers repeat requests itself, so the origin only sees the first
# (a MISS). We prove it with /health, which names the replica that served it.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile edge-caching"
GATEWAY="${GATEWAY:-http://localhost:${GATEWAY_HTTP_PORT:-8080}}"
EDGE="http://localhost:${EDGE_HTTP_PORT:-8082}"

echo "${BOLD}€” Edge / CDN caching${RESET}"
note "Assumes 'make edge-caching' is running (base + edge). Edge: $EDGE"

step "Scale the origin to 3 replicas" "so /health can name which replica served it"
run "$COMPOSE up -d --scale app=3 --no-recreate"
sleep 3
pause

step "Straight to the origin (gateway): the replica rotates" "host changes â€” every request hit the origin"
run "for i in \$(seq 1 6); do curl -s $GATEWAY/health; echo; done"
note "Round-robin: each call reached a (possibly different) app replica."
pause

step "First request THROUGH the edge: a MISS" "X-Cache-Status: MISS â€” the edge had to ask the origin"
run "curl -si $EDGE/health | tr -d '\r' | grep -Ei 'X-Cache-Status|\"host\"'"
pause

step "Repeat through the edge: HITs, served from cache" "X-Cache-Status: HIT and the SAME host every time"
run "for i in \$(seq 1 6); do curl -si $EDGE/health | tr -d '\r' | grep -Ei 'X-Cache-Status|\"host\"' | tr '\n' ' '; echo; done"
note "The host is frozen to whichever replica filled the cache â€” the origin is"
note "NOT being touched, even though 3 replicas exist and the gateway round-robins."
pause

step "Let the 10s TTL expire, then ask again" "X-Cache-Status flips to EXPIRED/MISS and the edge revalidates"
note "Waiting 11s for proxy_cache_valid (10s) to lapse ..."
sleep 11
run "curl -si $EDGE/health | tr -d '\r' | grep -Ei 'X-Cache-Status|\"host\"'"
note "A stale entry triggers one origin fetch; subsequent calls are HITs again."
pause

step "Cleanup" "remove the extra replicas"
run "$COMPOSE up -d --scale app=1 --no-recreate"

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
