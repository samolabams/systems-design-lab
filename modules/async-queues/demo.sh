#!/usr/bin/env bash
# €” async processing & backpressure (RabbitMQ + workers). Pausable.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile async-queues"

echo "${BOLD}€” Async processing & queues${RESET}"
note "Assumes 'make async-queues' is running. RabbitMQ UI: http://localhost:15672 (app/app)"

step "Enqueue a job via the API" "expect HTTP 202 'enqueued'"
run "curl -s -X POST $GATEWAY/jobs -H 'Content-Type: application/json' -d '{\"task\":\"resize\",\"id\":1}'; echo"
pause

step "Watch a worker pick it up" "one worker logs job_start then job_done"
run "$COMPOSE logs --tail 10 worker"
pause

step "Scale to 3 workers" "jobs will spread across 3 worker hostnames"
run "$COMPOSE up -d --scale worker=3"
pause

step "Publish a burst of 20 jobs" "queue absorbs the burst; workers drain steadily"
run "for i in \$(seq 1 20); do curl -s -X POST $GATEWAY/jobs -H 'Content-Type: application/json' -d \"{\\\"task\\\":\\\"job\\\",\\\"id\\\":\$i}\" >/dev/null; done; echo sent 20"
note "Open the UI 'jobs' queue: watch Ready/Unacked depth rise then fall."
pause

step "Observe distribution across workers" "3 distinct worker hosts in the logs"
run "$COMPOSE logs --tail 30 worker | grep job_done || true"

echo "${BOLD}Done.${RESET}"
