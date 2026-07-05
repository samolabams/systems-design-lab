#!/usr/bin/env bash
# Rate limiting. Two layers: (1) a cheap leaky-bucket at the gateway
# (Nginx limit_req) that sheds floods before they reach the app, and (2) the
# distributed counter primitive (Redis INCR+EXPIRE) that an APP-level limiter
# uses so the limit holds across replicas.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile rate-limiting"
NGINX_CONF="$REPO_ROOT/infra/gateway/nginx/nginx.conf"
VARIANTS="$REPO_ROOT/infra/gateway/nginx/variants"
RCLI="$COMPOSE exec -T redis redis-cli"

swap_gateway() {
  local variant="$1"
  [ -f "$NGINX_CONF.orig" ] || cp "$NGINX_CONF" "$NGINX_CONF.orig"
  cp "$VARIANTS/$variant.conf" "$NGINX_CONF"
  $COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway
}
restore_gateway() {
  [ -f "$NGINX_CONF.orig" ] && cp "$NGINX_CONF.orig" "$NGINX_CONF"
  $COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway
  rm -f "$NGINX_CONF.orig"
}

echo "${BOLD}Rate limiting${RESET}"
note "Assumes 'make rate-limiting' is running (base + redis). Gateway: $GATEWAY"

step "Baseline: no limit, every request passes" "all 200s"
run "for i in \$(seq 1 12); do curl -s -o /dev/null -w '%{http_code} ' $GATEWAY/health; done; echo"
pause

step "Turn on the gateway leaky-bucket (Nginx limit_req)" "config reloads cleanly"
note "rate=5r/s, burst=5 nodelay, returns 429 over the limit (see rate-limit.conf)."
run "swap_gateway rate-limit && echo 'rate-limit config active'"
pause

step "Flood the gateway" "first few 200, the rest 429 — the flood is shed at the edge"
note "20 back-to-back requests from one IP; only ~rate+burst get through per second."
run "for i in \$(seq 1 20); do curl -s -o /dev/null -w '%{http_code} ' $GATEWAY/health; done; echo"
note "429 = Too Many Requests. The app never even saw the rejected ones."
pause

step "Let the bucket drain, then trickle in under the rate" "steady requests pass again"
note "Wait ~2s for the bucket to refill, then send slowly (1 every 0.3s)."
sleep 2
run "for i in \$(seq 1 6); do curl -s -o /dev/null -w '%{http_code} ' $GATEWAY/health; sleep 0.3; done; echo"
pause

step "Restore the plain gateway" "back to no edge limit"
run "restore_gateway && echo 'base gateway restored'"
pause

step "The distributed primitive: a fixed window in Redis" "INCR returns the running count; EXPIRE bounds the window"
note "An app-level limiter (per API key / user) can't use in-memory counters — with"
note "N replicas each would allow the full quota, so the real limit becomes N×quota."
note "A SHARED Redis counter fixes that. Here is the textbook fixed-window check:"
note "  key = ratelimit:<user>:<window>;  INCR key;  if first hit, EXPIRE key <window>."
run "$RCLI DEL 'ratelimit:alice' >/dev/null; echo 'fresh window for user alice (limit = 5 / 10s)'"
run "for i in \$(seq 1 7); do n=\$($RCLI INCR 'ratelimit:alice'); [ \"\$n\" = '1' ] && $RCLI EXPIRE 'ratelimit:alice' 10 >/dev/null; if [ \"\$n\" -le 5 ]; then echo \"req \$i -> count \$n  ALLOW\"; else echo \"req \$i -> count \$n  DENY (429)\"; fi; done"
note "Every app replica runs the SAME INCR against the SAME key, so the quota is"
note "global. Inspect the counter and its remaining TTL:"
run "$RCLI GET 'ratelimit:alice'; $RCLI TTL 'ratelimit:alice'"
note "When the TTL hits 0 the key vanishes and the next request starts a new window."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
