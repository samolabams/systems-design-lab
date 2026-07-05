#!/usr/bin/env bash
# Introduction to systems design: observe latency, throughput, bottlenecks, and stateless scaling.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="${COMPOSE:-docker compose}"

echo "${BOLD}Introduction to systems design${RESET}"
note "Assumes 'make base' is running. This walkthrough turns the vocabulary into observable behavior."
note "Learning loop: predict the system behavior, run the command, then explain the trade-off."

step "Name the request path" \
     "one user request crosses several components before a response returns"
predict "Which components are in the base request path for a short-link redirect?" \
     "client -> gateway -> app -> database access layer -> durable store -> app -> gateway -> client."
run "$COMPOSE ps gateway app pgbouncer postgres-primary"
checkpoint "Why is this more useful than saying 'the app is slow'?" \
           "It gives you specific places to measure: gateway, app, pooler, database, and network hops."
pause

step "Latency vs throughput" \
     "latency is time per request; throughput is requests per second"
note "p95 latency means the 95th percentile: 95% of requests completed at or below that time, and the slowest 5% took longer."
predict "If more users arrive at once, which metric usually moves first: p95 latency or average latency?" \
        "p95 often exposes pressure first because the slow tail grows before the average looks alarming."
note "The smoke test reports checks, request rate, and latency percentiles. Read p95 before averages."
run "make load"
checkpoint "What would high throughput with rising p95 tell you?" \
           "The system is doing many requests, but some users are waiting too long; capacity is being approached."
pause

step "Stateless replicas" \
     "the app can be copied because durable state lives outside the process"
predict "What should change when the app tier scales to 3 replicas?" \
     "Docker should run multiple app containers; a short gateway sample may show several hostnames or one repeated hostname."
run "make scale N=3"
run "make health-loop"
checkpoint "What proves the app tier is stateless enough for horizontal scaling?" \
        "Multiple app containers can run the same code while durable state remains in the shared database."
pause

step "Bottlenecks move" \
     "scaling one tier does not remove every limit in the system"
predict "After adding app replicas, what shared dependency can still cap the whole system?" \
     "The database is still shared by every app replica."
run "$COMPOSE ps app pgbouncer postgres-primary"
checkpoint "Why might adding app replicas stop helping after a point?" \
           "Once the app tier is no longer the bottleneck, the database, connection pool, network, or gateway can become the limit."
pause

step "Write a trade-off statement" \
     "systems design is justified choices, not component collecting"
try_it "Complete this sentence: 'We scale the app tier horizontally because ___, but this does not solve ___.'" \
       "Good answer: because the app is stateless and CPU/request capacity can grow with replicas, but it does not solve database pressure."
checkpoint "What makes a systems-design claim strong?" \
           "It names the requirement, the mechanism, the evidence, and the cost or remaining risk."

echo
note "${BOLD}Done.${RESET} Cleanup: make scale N=1; make reset"