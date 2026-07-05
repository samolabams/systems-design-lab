#!/usr/bin/env bash
# Load balancing demonstration.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"
NGINX_CONF="$REPO_ROOT/infra/gateway/nginx/nginx.conf"
VARIANTS="$REPO_ROOT/infra/gateway/nginx/variants"

# Swap the active gateway config with a full variant, then hot-reload Nginx.
# The first swap backs up the original config so cleanup can restore it
# (this repo is not a git checkout, so we can't `git checkout --` it back).
swap_upstream() {
  local variant="$1"
  [ -f "$NGINX_CONF.orig" ] || cp "$NGINX_CONF" "$NGINX_CONF.orig"
  cp "$VARIANTS/$variant.conf" "$NGINX_CONF"
  $COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway
}

# Restore the original gateway config from the backup and reload.
restore_upstream() {
  [ -f "$NGINX_CONF.orig" ] && cp "$NGINX_CONF.orig" "$NGINX_CONF"
  $COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway
}

echo "${BOLD}Load balancing${RESET}"
note "Assumes 'make base' is running. Gateway: $GATEWAY"
note "Learning loop: predict the routing behavior, run traffic, explain what changed."

step "Scale the app to 3 replicas" "three distinct hostnames will exist"
predict "What should scaling app=3 create?" \
  "Three running copies of the same app service, all reachable through the gateway."
run "$COMPOSE up -d --scale app=3 --no-recreate"
run "$COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway"
checkpoint "What is the difference between one app and three replicas?" \
     "They run the same code, but there are now three backend instances that can share traffic."
pause

step "Docker embedded DNS resolves the service name 'app'" \
     "a service name hides the changing container IPs behind it"
predict "What does the gateway need before it can send traffic to app replicas?" \
  "It needs a way to turn the service name app into a backend IP address."
run "for i in \$(seq 1 5); do $COMPOSE exec gateway getent hosts app || $COMPOSE exec gateway nslookup app; done"
checkpoint "Why is DNS discovery useful but not the same as full load balancing?" \
     "DNS can return backend addresses, but resolver caching and client behavior decide how those answers are used."
pause

step "Base Nginx path: observe distribution and caching" \
     "hostnames may rotate, or they may stay pinned while DNS is cached"
predict "What should repeated /health responses reveal about the gateway path?" \
  "If the gateway re-resolves to different replicas, hostnames change; if DNS is cached, one hostname may repeat."
run "for i in \$(seq 1 9); do curl -s $GATEWAY/health; echo; done"
checkpoint "If one hostname repeats, what did this prove?" \
     "It proves the base Nginx path can be pinned by DNS/resolver caching, which is why real balancers need explicit backend membership or service discovery."
pause

step "Make one replica SLOW" "that replica answers ~750ms slower"
note "Start an extra app instance with SLOW=1. --use-aliases gives it the 'app'"
note "network alias so Docker DNS includes it in the gateway's round-robin pool."
predict "What should happen if a slow replica joins a simple round-robin pool?" \
  "It should still receive some traffic, so some requests should become slower."
run "$COMPOSE run -d --use-aliases --name app-slow -e SLOW=1 app node server.js || true"
sleep 3
pause

step "Slow node under the base Nginx path" \
  "a spike appears only if the gateway routes to the slow replica"
note "A simple strategy cannot know a node is slow unless it measures load or health."
run "for i in \$(seq 1 12); do curl -s -o /dev/null -w '%{time_total}s ' $GATEWAY/health; done; echo"
checkpoint "What do the timings prove?" \
     "A ~0.750s value proves the slow backend received traffic; no spike means the gateway stayed pinned elsewhere during this sample."
pause

step "HAProxy contrast: explicit balancing with active checks" \
  "requests should spread across app backends through the HAProxy gateway"
predict "What should a dedicated balancer with backend membership show?" \
     "Repeated requests should reach more than one backend, and the stats page should show backend health."
run "$COMPOSE --profile load-balancing-haproxy up -d --scale app=3 haproxy"
run "curl --retry 10 --retry-delay 1 --retry-connrefused -s -o /dev/null -w 'haproxy ready status=%{http_code}\n' http://localhost:8082/health || true"
run "for i in \$(seq 1 9); do curl -s -w ' status=%{http_code}' http://localhost:8082/health; echo; done"
checkpoint "Why is HAProxy a clearer pure load-balancer contrast here?" \
     "It maintains backend membership with server-template and actively probes /health, instead of relying only on Nginx's DNS cache behavior."
pause

step "least_conn / ip_hash directives (config swap)" "config reloads cleanly"
note "These strategies need an upstream block, which OSS Nginx resolves ONCE at"
note "boot — under Docker --scale it pins to a single replica IP, so it cannot"
note "live-rebalance across dynamic replicas. That gap is exactly what service discovery"
note "(service discovery) closes. We swap the config to show the directive loads;"
note "true least_conn/ip_hash balancing needs explicit upstreams or a registry."
predict "Why is this config swap a syntax/concept check rather than a perfect live-balancing demo?" \
  "Static Nginx upstreams resolve app once at boot, so dynamic replica membership needs service discovery."
run "swap_upstream least_conn && echo 'least_conn config active'"
run "swap_upstream ip_hash && echo 'ip_hash config active'"
checkpoint "What problem will service discovery solve for this module?" \
     "It gives the gateway an up-to-date list of healthy service instances instead of a static boot-time list."
pause

step "Passive failure detection (Nginx)" "errors until max_fails trips"
note "Restore the round-robin (resolver) config first so failover is observable."
run "restore_upstream"
note "Killing one app replica; Nginx keeps trying it until max_fails."
predict "What may happen to the first few requests after one backend is killed?" \
  "Some requests may fail before passive failure detection routes around the bad backend."
run "cid=\$($COMPOSE ps -q app | head -n1); docker kill \$cid"
run "for i in \$(seq 1 6); do curl -s -o /dev/null -w '%{http_code} ' $GATEWAY/health; done; echo"
checkpoint "Why can passive detection expose users to early failures?" \
     "The balancer learns from real request failures instead of probing backends before user traffic arrives."
pause

step "Cleanup" "remove the slow one-off container and restore config"
run "docker rm -f app-slow 2>/dev/null || true"
run "$COMPOSE --profile load-balancing-haproxy rm -sf haproxy 2>/dev/null || true"
run "restore_upstream"
run "rm -f $NGINX_CONF.orig"

note "For the active-health-check contrast, run: make load-balancing-haproxy  (stats: http://localhost:8404/stats)"
echo "${BOLD}Done.${RESET}"
