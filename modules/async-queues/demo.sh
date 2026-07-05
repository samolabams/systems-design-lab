#!/usr/bin/env bash
# Async processing and backpressure (RabbitMQ + workers).
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile async-queues"

echo "${BOLD}Async processing & queues${RESET}"
note "Assumes 'make async-queues' is running. RabbitMQ UI: http://localhost:15672 (app/app)"
note "Learning loop: predict queue behavior, publish work, then inspect workers and queue depth."

step "Enqueue a job via the API" "expect HTTP 202 'enqueued'"
predict "What should the API return when work is accepted but not finished yet?" \
     "HTTP 202 Accepted, because the job was queued for asynchronous processing."
run "curl -s -X POST $GATEWAY/api/jobs -H 'Content-Type: application/json' -d '{\"task\":\"resize\",\"id\":1}'; echo"
checkpoint "Why should the API avoid doing slow background work inline?" \
	"The request path stays fast while workers handle slower or retryable side effects."
pause

step "Watch a worker pick it up" "one worker logs job_start then job_done"
predict "What should appear in the worker log after a job is queued?" \
     "A job_start event followed by job_done when the worker acknowledges the message."
run "$COMPOSE logs --tail 10 worker"
checkpoint "What does acknowledgement protect?" \
	"The broker can redeliver work if a worker dies before finishing, which supports at-least-once delivery."
pause

step "Scale to 3 workers" "competing consumers share the queue"
predict "If one queue has three workers, does each job run three times?" \
     "No. Competing consumers divide messages; each message is delivered to one worker at a time."
run "$COMPOSE up -d --scale worker=3"
checkpoint "What does scaling workers improve?" \
	"Drain rate: more workers can process queued jobs concurrently, as long as the downstream dependency can keep up."
pause

step "Publish a burst of 20 jobs" "queue absorbs the burst; workers drain steadily"
predict "What should happen immediately after a burst if producers are faster than workers?" \
     "Ready queue depth rises first, then falls as workers process messages."
run "for i in \$(seq 1 20); do curl -s -X POST $GATEWAY/api/jobs -H 'Content-Type: application/json' -d \"{\\\"task\\\":\\\"job\\\",\\\"id\\\":\$i}\" >/dev/null; done; echo sent 20"
note "Open the UI 'jobs' queue: watch Ready/Unacked depth rise then fall."
checkpoint "What is backpressure in this example?" \
	"The queue buffers work when producers outrun consumers instead of forcing API requests to wait for every job."
pause

step "Observe distribution across workers" "3 distinct worker hosts in the logs"
run "$COMPOSE logs --tail 30 worker | grep job_done || true"
checkpoint "Why is this at-least-once rather than exactly-once processing?" \
	"A crash around acknowledgement can cause redelivery, so job handlers must be idempotent."

step "Mini challenge" "change workload or worker count and predict the drain behavior"
try_it "Send 100 jobs, then compare drain time with 1 worker and 3 workers." \
       "$COMPOSE up -d --scale worker=1; then repeat the burst and logs check."
checkpoint "When would adding more workers stop helping?" \
	"When the bottleneck moves to the database, network, external API, CPU, or broker."

echo
note "${BOLD}Done.${RESET} Cleanup: make reset"
