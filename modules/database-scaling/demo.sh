#!/usr/bin/env bash
# Database scaling. Pausable, step-by-step.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="${COMPOSE:-docker compose}"
PSQL="$COMPOSE exec -T postgres-primary psql -U app -d app"

echo "${BOLD}Module API gateway - Database scaling${RESET}"
note "Assumes 'make base' is running. This module explains which database scaling lever fits which pressure."

step "Name the shared state" \
     "app replicas can multiply, but they still depend on one source of truth"
predict "If the app tier scales from 1 to 5 replicas, what data-tier dependency stays shared?" \
        "The Postgres primary remains the durable source of truth."
run "$COMPOSE ps app pgbouncer postgres-primary"
checkpoint "Why can app replicas scale more easily than the database?" \
           "The app replicas are stateless and interchangeable; the database owns durable state and correctness."
pause

step "Find connection pooling in the path" \
     "connection pressure is a different problem from slow queries"
predict "Why might many app replicas hurt the database even if each request is simple?" \
        "Each replica can open database connections; too many sessions consume memory and scheduling capacity."
run "$COMPOSE exec -T pgbouncer sh -lc \"grep -E '^(pool_mode|max_client_conn|default_pool_size)' /etc/pgbouncer/pgbouncer.ini\""
checkpoint "Which scaling lever protects the database from too many app connections?" \
           "Connection pooling: many app requests share a smaller pool of database sessions."
pause

step "Check whether a hot lookup already has an index" \
     "a slow query is not automatically a sharding problem"
predict "For a URL redirect, which field should be indexed first?" \
        "The short code, because redirects look up one row by code."
run "$PSQL -c \"SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'links';\""
run "$PSQL -c \"EXPLAIN SELECT code, url FROM links WHERE code = 'demo';\""
checkpoint "What should you inspect before adding replicas or shards for one slow query?" \
           "The query plan, indexes, data model, and access pattern."
pause

step "Measure pressure before choosing a scaling lever" \
     "a small load test gives latency and request-rate evidence"
predict "What should you measure before deciding that the database needs replicas or shards?" \
        "Request rate, latency percentiles, error rate, database connections, and slow-query evidence."
note "This smoke load goes through the public gateway. It is intentionally small; the point is the measurement habit."
run "make load"
checkpoint "If p95 latency is healthy and errors are zero, should you add sharding from this evidence alone?" \
           "No. Keep measuring and tune the cheapest bottleneck first; sharding is for a proven write/storage ceiling."
pause

step "Choose the right next mechanism" \
     "different pressures map to different modules"
try_it "Match a symptom to a next step: read-heavy traffic, primary failure, write/storage ceiling, repeated hot reads, write bursts." \
     "Read-heavy -> replication and failover. Primary failure -> replication and failover or leader election. Write/storage ceiling -> partitioning and sharding. Hot reads -> caching. Bursts -> async queues."
checkpoint "Why is 'just shard it' usually the wrong first answer?" \
           "Sharding adds routing, hot-key, cross-shard query, and rebalancing complexity; use it when one node's write/storage ceiling is the real limit."

echo
note "${BOLD}Done.${RESET} Next: replication and failover proves read replicas, lag, and failover in a runnable lab."
