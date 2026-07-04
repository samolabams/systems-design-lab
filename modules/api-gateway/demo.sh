#!/usr/bin/env bash
# API Gateway / Edge Gateway. Pausable, step-by-step.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"
GATEWAY="${GATEWAY:-http://localhost:${GATEWAY_HTTP_PORT:-8080}}"
NGINX_CONF="$REPO_ROOT/infra/gateway/nginx/nginx.conf"

shorten_and_resolve() {
     local resp code
     resp=$(curl -s -X POST "$GATEWAY/api/shorten" \
          -H "Content-Type: application/json" \
          -d '{"url":"https://example.com"}')
     echo "$resp"
     code=$(printf "%s" "$resp" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
     curl -i -s "$GATEWAY/api/links/$code" | grep -E "HTTP/|Location:"
}

echo "${BOLD}Module API gateway - API Gateway / Edge Gateway${RESET}"
note "Assumes 'make base' is running. Gateway: $GATEWAY"
note "Learning loop: identify whether the gateway or the app answered each request."

step "The gateway is the public front door" \
     "the gateway health endpoint is answered by Nginx itself"
predict "What should /gateway-health prove?" \
        "It should prove the gateway process is reachable before the app is involved."
run "curl -i -s $GATEWAY/gateway-health | sed -n '1,12p'"
checkpoint "Which output proves the gateway itself answered?" \
           "The response body says 'gateway ok', which is produced by Nginx config."
pause

step "The gateway maps a public API route to the app" \
     "the public /api/health route forwards to the app's internal /health route"
predict "What should change when the request goes to /api/health instead of /gateway-health?" \
        "The app should answer with JSON containing host and role fields."
run "curl -i -s $GATEWAY/api/health | sed -n '1,12p'"
checkpoint "How can you tell the app answered through the gateway?" \
           "The body contains role=app and a container hostname, not 'gateway ok'."
pause

step "The app is not exposed directly on the host" \
     "external callers use the gateway address, not app:3000"
predict "Should localhost:3000/health work from the host?" \
        "No. The app has no published host port; the gateway is the public entry point."
run "curl -s --connect-timeout 2 http://localhost:3000/health || echo 'direct app port is not exposed on the host'"
checkpoint "What boundary does this prove?" \
           "The app lives behind the gateway on the internal Docker network."
pause

step "The gateway carries a real API workflow" \
     "POST /api/shorten creates a code; GET /api/links/:code returns a redirect"
predict "What should the gateway return after creating and resolving a short link?" \
        "POST /api/shorten should return a code, then GET /api/links/code should return a 302 Location header."
run "shorten_and_resolve"
checkpoint "What does the Location header prove?" \
           "The app handled the domain action and returned the redirect through the gateway."
pause

step "The gateway also exposes operational routes" \
     "metrics are proxied; jobs depend on the async queue profile"
predict "What should /api/metrics return through the gateway?" \
        "Prometheus text metrics from the app, because the gateway maps /api/metrics to /metrics."
run "curl -s $GATEWAY/api/metrics | sed -n '1,8p'"
note "/api/jobs is part of the route map, but it returns 503 unless the async-queues profile is active."
run "curl -i -s -X POST $GATEWAY/api/jobs -H 'Content-Type: application/json' -d '{\"kind\":\"demo\"}' | sed -n '1,12p'"
checkpoint "Why is /api/jobs different from /api/shorten in the base stack?" \
           "It crosses into queue-backed behavior, so the route exists but the backing broker is unavailable until async-queues is started."
pause

step "The gateway config owns the forwarding rule" \
     "shared proxy settings plus route-specific proxy_pass rules define the front-door behavior"
predict "Which Nginx directives should reveal the gateway route map?" \
        "Look for shared proxy headers, /api routes, and proxy_pass targets."
run "grep -nE 'location|proxy_pass|proxy_set_header|listen|gateway-health|api/' $NGINX_CONF"
checkpoint "Which directive sends normal requests to the app service?" \
           "proxy_pass sends requests to the backend service named app:3000."
pause

step "Gateway responsibilities vs application responsibilities" \
     "the boundary keeps infrastructure policy out of domain logic"
try_it "Name one gateway responsibility and one app responsibility in this lab." \
       "Gateway: forwarding, headers, timeouts. App: shorten URLs, resolve codes, return health JSON."
checkpoint "Why should business rules usually stay out of the gateway?" \
           "The gateway should enforce boundary policy; domain rules belong in the service that owns the domain."

echo
note "${BOLD}Done.${RESET} Cleanup: make reset"
