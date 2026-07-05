#!/usr/bin/env bash
# Service discovery. load balancing's gateway used a
# static Nginx upstream that resolves once at boot; it can't track instances that
# come and go. Here a Consul registry is the source of truth: each app replica is
# registered with an HTTP health check, and discovery returns ONLY instances whose
# check is passing. We scale to 3, register them, then stop one and watch Consul
# evict it from the healthy set.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile service-discovery"
NET="systems-design_backend"           # docker network the replicas sit on
CONSUL="$COMPOSE exec -T consul"

# Distinct app instance IDs that Consul currently reports as PASSING.
# Queried from the Consul container itself, so it never lands on a stopped replica.
passing() {
  $CONSUL wget -qO- "http://127.0.0.1:8500/v1/health/service/app?passing" 2>/dev/null \
    | grep -o 'app-[0-9]*' | sort -u
}

# Register one replica (id + ip) as service "app" with a 3s HTTP health check.
register() {  # id ip
  local id="$1" ip="$2"
  $CONSUL sh -c "cat > /tmp/$id.json" <<EOF
{"service":{"id":"$id","name":"app","address":"$ip","port":3000,
  "check":{"http":"http://$ip:3000/health","interval":"3s","timeout":"2s",
           "deregister_critical_service_after":"30s"}}}
EOF
  $CONSUL consul services register "/tmp/$id.json" >/dev/null
  echo "    registered $id -> $ip:3000  (health: GET /health every 3s)"
}

# Poll until exactly $1 instances are passing (or timeout), then echo the count.
wait_passing() {  # target timeout_s
  local target="$1" deadline=$((SECONDS + ${2:-25})) n
  while [ "$SECONDS" -lt "$deadline" ]; do
    n=$(passing | grep -c . || true)
    [ "$n" = "$target" ] && { echo "$n"; return 0; }
    sleep 2
  done
  passing | grep -c . || true
}

# Poll until a specific instance id is no longer in the passing set (or timeout).
wait_gone() {  # id timeout_s
  local id="$1" deadline=$((SECONDS + ${2:-30}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    passing | grep -qx "$id" || return 0
    sleep 2
  done
  return 1
}

echo "${BOLD}Service discovery${RESET}"
note "Assumes 'make service-discovery' is running (base + Consul)."

step "Scale the app tier to 3 replicas" "three interchangeable instances behind one service name"
run "$COMPOSE up -d --scale app=3 --no-recreate"
cids=($($COMPOSE ps -q app))
note "app replicas: ${#cids[@]}"
pause

step "Register each replica in Consul with a health check" "instances announce themselves; the registry becomes the source of truth"
# Clear any registrations left by a previous run so re-running is idempotent
# (Consul -dev keeps them in memory until the container is recreated).
for k in 1 2 3 4 5 6; do $CONSUL consul services deregister -id "app-$k" >/dev/null 2>&1 || true; done
first_id=""; first_cid=""
i=0
for cid in "${cids[@]}"; do
  i=$((i + 1)); id="app-$i"
  ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NET\").IPAddress}}" "$cid")
  register "$id" "$ip"
  if [ -z "$first_id" ]; then first_id="$id"; first_cid="$cid"; fi
done
note "Consul now lists service(s): $($CONSUL consul catalog services | tr '\n' ' ')"
pause

step "Discover healthy instances" "the registry returns only instances whose check is passing"
n=$(wait_passing "${#cids[@]}" 25)
note "passing instances ($n):"
passing | sed 's/^/    /'
note "No Nginx config was edited — a discovery-aware balancer would pull this set"
note "from Consul and route only to it. New replicas appear here automatically."
pause

step "Stop one replica — watch Consul evict it" "the active health check fails, the instance drops from discovery"
note "Stopping $first_id (its container). Its /health check will start failing..."
run "docker stop $first_cid"
wait_gone "$first_id" 30 || true
note "passing instances now ($(passing | grep -c .)):"
passing | sed 's/^/    /'
note "$first_id is gone from the healthy set within a couple of check intervals —"
note "no client ever had to be told; the registry reflected reality on its own."
pause

step "Contrast with load balancing" "static upstream vs dynamic, health-checked registry"
note "load balancing's OSS Nginx 'upstream { server app:3000; }' resolves once at boot and has"
note "only PASSIVE detection (fail after N errors). Consul does ACTIVE checks and"
note "dynamic membership: instances register/deregister and only healthy ones are"
note "ever discoverable — the capability the static config could not provide."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
