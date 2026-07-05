#!/usr/bin/env bash
# When not to scale: measure before adding distributed machinery.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="${COMPOSE:-docker compose}"

echo "${BOLD}When NOT to scale${RESET}"
note "Assumes 'make base' is running. This lab shows how restraint can be an engineering decision."
note "The goal is to reject or justify extra infrastructure with evidence."

step "Start with the simple architecture" \
     "no Redis, no queue, no shard, no extra datastore"
predict "Which services should be running for the base path?" \
     "Gateway, app, and one database path; optional scaling machinery should be absent."
run "$COMPOSE ps gateway app pgbouncer postgres-primary"
checkpoint "Why is a small architecture valuable before there is evidence of pressure?" \
           "It has fewer failure modes, fewer operators, lower cost, and simpler debugging."
pause

step "Take a baseline measurement" \
     "latency and error rate come before architecture changes"
note "p95 latency is the 95th percentile: 95% of requests completed at or below that time, while the slowest 5% took longer."
predict "What result would argue against adding a cache or shard right now?" \
        "Low error rate and healthy p95 under the current expected load."
run "make load"
checkpoint "If this passes cleanly, what have you proven?" \
           "Only that this workload does not yet require more machinery; keep measuring as requirements grow."
pause

step "Try the cheapest scaling move" \
     "stateless app replicas are simpler than new distributed subsystems"
predict "What should improve if the app tier is the bottleneck?" \
        "More app replicas should lower request queuing at the app tier and may improve p95."
run "make scale N=2"
run "make health-loop"
run "make load"
checkpoint "If p95 improves with app replicas, what should you avoid claiming?" \
           "Do not claim the database needed sharding; the measured pressure was at least partly app-tier capacity."
pause

step "Map symptoms to mechanisms" \
     "each scaling tool addresses a specific pressure"
try_it "Match each symptom to a likely next step: hot repeated reads, slow single query, write bursts, DB failover need, storage/write ceiling." \
       "Hot reads -> cache. Slow query -> index/tune. Bursts -> queue. Failover -> replica/failover. Storage/write ceiling -> partitioning/sharding."
checkpoint "What question must be answered before adding any of those components?" \
           "Which resource or requirement is actually forcing the change?"
pause

step "Write the 'not yet' decision" \
     "a good design can defer complexity while naming the trigger"
try_it "Write one sentence: 'We will not add ___ until ___ exceeds ___ because ___.'" \
       "Example: We will not add Redis until redirect p95 or database read load exceeds the target because cache invalidation adds operational risk."
checkpoint "Why is this stronger than saying 'we do not need scale'?" \
           "It defines the metric that would change the decision later."

echo
note "${BOLD}Done.${RESET} Cleanup: make scale N=1; make reset"