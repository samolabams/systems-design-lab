#!/usr/bin/env bash
# Scaling: vertical vs horizontal.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"
GATEWAY="${GATEWAY:-http://localhost:${GATEWAY_HTTP_PORT:-8080}}"

distinct_hosts() {
  local count="${1:-12}"
  for i in $(seq 1 "$count"); do
    curl -s "$GATEWAY/api/health"
    echo
  done | sed -n 's/.*"host":"\([^"]*\)".*/\1/p' | sort | uniq -c
}

app_container_ids() {
     docker ps -q \
          --filter "label=com.docker.compose.project=systems-design" \
          --filter "label=com.docker.compose.service=app"
}

wait_for_app_replicas() {
     local target="$1" count healthy
     for _ in $(seq 1 20); do
          count=$(app_container_ids | wc -l | tr -d ' ')
          healthy=$(app_container_ids | xargs docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null | grep -c '^healthy$' || true)
          if [ "$count" -ge "$target" ] && [ "$healthy" -ge "$target" ]; then
               echo "$healthy/$target app replicas are healthy"
               return 0
          fi
          echo "waiting for app replicas: $healthy/$target healthy"
          sleep 1
     done
     echo "app replicas were not all healthy yet; continuing so you can inspect the state"
}

probe_each_replica() {
     local cid name ip
     for cid in $(app_container_ids); do
          name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's#^/##')
          ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cid")
          printf '%s %s -> ' "$name" "$ip"
          $COMPOSE exec -T gateway wget -qO- "http://$ip:3000/health" </dev/null 2>/dev/null || echo "not ready yet"
          echo
     done
}

echo "${BOLD}Scaling: vertical vs horizontal${RESET}"
note "Assumes 'make base' is running. Gateway: $GATEWAY"
note "Learning loop: change replica count, send traffic, explain what capacity changed."

step "Start with one app replica" \
     "one running copy means one app process can answer traffic"
predict "What should repeated health checks show with N=1?" \
        "They should show one app hostname because only one app replica is running."
run "make scale N=1"
run "$COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway"
run "distinct_hosts 8"
checkpoint "What does one hostname prove?" \
           "The app tier currently has one serving replica behind the gateway."
pause

step "Scale out horizontally to three replicas" \
     "same code, more running copies"
predict "What changes when N goes from 1 to 3?" \
        "The app code does not change; Docker runs three copies of the same service."
run "make scale N=3"
run "$COMPOSE exec gateway nginx -s reload 2>/dev/null || $COMPOSE restart gateway"
run "$COMPOSE ps app"
run "wait_for_app_replicas 3"
checkpoint "What is the difference between vertical and horizontal scaling here?" \
           "Vertical scaling would make one app container larger; horizontal scaling adds more app containers."
pause

step "Prove each replica can serve the same request" \
     "each app container answers /health from inside the Docker network"
predict "What should be true if all three replicas are interchangeable?" \
     "Each replica should be able to answer the same /health request with role=app."
run "probe_each_replica"
checkpoint "What output proves the app tier is horizontally scaled?" \
        "Several app containers exist, and each can answer the same request."
pause

step "Observe the gateway sample" \
     "the public path stays stable; distribution may be uneven in a short sample"
predict "What might repeated /api/health requests through the gateway show?" \
     "They may show several hostnames, or one repeated hostname if the gateway/DNS path is cached during the sample."
run "distinct_hosts 20"
checkpoint "Why is gateway distribution not the main proof in this module?" \
        "scaling is about changing replica count and statelessness; load balancing and service discovery cover balancing and dynamic service membership in depth."
pause

step "Scale farther, then scale down" \
     "replica count can change while the public gateway URL stays the same"
predict "Should the client URL change when replica count changes?" \
        "No. Clients still call the gateway; only the number of internal app replicas changes."
run "make scale N=5"
run "$COMPOSE ps app"
run "make scale N=2"
run "$COMPOSE ps app"
checkpoint "What stayed stable while replicas changed?" \
           "The public gateway address stayed the same: $GATEWAY."
pause

step "Scaling moves the bottleneck" \
     "more app replicas can increase pressure on shared dependencies"
try_it "Name one dependency that receives more pressure when app replicas increase." \
     "Examples: a database, cache, queue, external API, or shared file store."
checkpoint "Why does horizontal scaling not guarantee unlimited throughput?" \
           "The app tier can scale out, but shared dependencies eventually become the limit."

echo
note "${BOLD}Done.${RESET} Cleanup: make scale N=1 && make reset"
