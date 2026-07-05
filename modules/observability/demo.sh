#!/usr/bin/env bash
# Module observability (third pillar) — traces & logs: the metric -> trace -> log pivot.
#
# Metrics tell you *that* something is slow; a trace tells you *where* the time
# went for one request; the logs tell you *why*. This demo drives real traffic,
# then walks the pivot end to end in Grafana:
#
#   1. a normal request  -> its trace (app -> Postgres) + correlated logs
#   2. a slow request    -> the latency shows up as an exemplar on the RED
#      Duration panel, one click from the exact trace
#   3. an async job       -> POST /jobs produces ONE trace spanning
#      app -> RabbitMQ -> worker (context rides the message)
#
# The app and worker are always instrumented; this profile just turns on the
# backends (OTel Collector -> Tempo + Loki) and Grafana's datasource links.
#
# Usage:  ./modules/observability/demo.sh          (interactive)
#         AUTO=1 ./modules/observability/demo.sh   (no pauses, for CI)

set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

# This demo needs both the observability backends AND the queue/worker so the
# cross-service (app -> queue -> worker) trace exists.
COMPOSE="docker compose --profile observability --profile async-queues"
GRAFANA="http://localhost:${GRAFANA_PORT:-3001}"

# Prometheus, Tempo and Loki live on the internal `backend` network (only Grafana,
# which straddles both networks, reaches them from the browser). So CLI probes go
# *through* the app container rather than the host.
execwget() { docker compose exec -T app sh -c "wget -qO- '$1'" 2>/dev/null; }

# Query Prometheus for a single scalar (returns "" if no data yet).
promq() {
  execwget "http://prometheus:9090/api/v1/query?query=$1" \
    | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else "")' 2>/dev/null
}

# Loki trace->log filter. trace_id arrives as *structured metadata* (the log body
# never contains it), so the pivot filters with `| trace_id="..."`, NOT a `|=`
# line filter. This mirrors exactly what Grafana's tracesToLogsV2 runs; if the
# wiring regresses, this returns nothing and the assertion below fails loudly.
lokiq() {
  local q; q=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$1")
  execwget "http://loki:3100/loki/api/v1/query_range?query=$q&limit=20"
}

# Pick the trace_id of the most recent worker job line (job_start/job_done carry
# the trace context that rode the AMQP message).
job_trace_id() {
  lokiq '{service_name="worker"} | trace_id!=""' \
    | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["stream"]["trace_id"] if r else "")' 2>/dev/null
}

# ---------------------------------------------------------------------------

step "Bring up the three pillars" "otel-collector, tempo, loki join the metrics stack"
run "$COMPOSE up -d --build"
note "Grafana: $GRAFANA   (anonymous viewer; admin/admin)"
note "Prometheus, Tempo and Loki are backend-only; reach them through Grafana."
note "Waiting for the app to report healthy…"
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$GATEWAY/health" || true)
  [ "$code" = "200" ] && break
  sleep 2
done
run "curl -s $GATEWAY/health; echo"
pause

step "Generate a little traffic" "each request becomes a trace; logs are stamped with its trace_id"
note "shorten a URL (write path -> Postgres), then redirect it a few times (read path)"
run "code=\$(curl -s -X POST $GATEWAY/shorten -H 'Content-Type: application/json' -d '{\"url\":\"https://opentelemetry.io\"}' | sed -n 's/.*\"code\":\"\\([^\"]*\\)\".*/\\1/p'); echo \"code=\$code\""
run "for i in \$(seq 1 8); do curl -s -o /dev/null \"$GATEWAY/\$code\"; done; echo '8 redirects sent'"
pause

step "Fire an async job" "POST /jobs -> RabbitMQ -> worker, all under ONE trace"
note "the trace context rides the AMQP message, so the worker span is a child of this request"
for _ in $(seq 1 30); do
  jobs_code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GATEWAY/api/jobs" -H 'Content-Type: application/json' -d '{"task":"resize","n":1}' || true)
  [ "$jobs_code" = "202" ] && break
  sleep 2
done
run "test \"$jobs_code\" = 202 && echo 'jobs -> 202'"
pause

step "Make one request visibly slow" "SLOW=1 adds latency -> a high exemplar on the Duration panel"
note "recreate just the app with injected latency (SLOW=1)…"
run "SLOW=1 $COMPOSE up -d app >/dev/null 2>&1; echo 'app now slow'"
wait_for_http "$GATEWAY/api/health" "slow app"
note "sending a burst of slow requests to plant a fat p95/p99 exemplar…"
run "for i in \$(seq 1 12); do curl -s -o /dev/null -X POST $GATEWAY/shorten -H 'Content-Type: application/json' -d '{\"url\":\"https://slow.example/'\$i'\"}'; done; echo 'slow burst sent'"
pause

step "Confirm telemetry is flowing (from the CLI)" "non-empty numbers mean the pipeline is live"
note "request rate right now (via Prometheus):"
run "promq 'sum(rate(http_requests_total%5B1m%5D))'"
note "exemplars stored (each carries a trace_id -> the metric->trace link):"
run "execwget \"http://prometheus:9090/api/v1/query_exemplars?query=http_request_duration_seconds_bucket&start=\$(( \$(date +%s) - 300 ))&end=\$(date +%s)\" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)[\"data\"]),\"exemplar series\")'"
note "traces landed in Tempo:"
run "execwget 'http://tempo:3200/api/search?limit=3' | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get(\"traces\",[])),\"recent traces\")'"
note "trace -> log pivot works (one job trace's logs, across app AND worker):"
run "tid=\$(job_trace_id); echo \"job trace_id=\$tid\"; \
  lokiq \"{service_name=~\\\".+\\\"} | trace_id=\\\"\$tid\\\"\" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)[\"data\"][\"result\"]; svc=sorted({s[\"stream\"][\"service_name\"] for s in r}); n=sum(len(s[\"values\"]) for s in r); print(\"PASS\" if n and \"worker\" in svc else \"FAIL\", n, \"lines across\", svc)'"
pause

step "Walk the pivot in Grafana" "this is the payoff — do it in the browser"
cat <<PIVOT
${BOLD}Open Grafana:${RESET} $GRAFANA

  ${BOLD}metric → trace${RESET}
    1. Dashboards → "Systems Design Lab" → "RED — gateway → app → DB".
    2. On the ${BOLD}Duration${RESET} panel, hover a diamond ◆ (an exemplar) near the
       p95/p99 spike and click ${BOLD}"Query with Tempo"${RESET}.
       → jumps to the exact slow trace.

  ${BOLD}trace → log${RESET}
    3. In that trace, expand a span → ${BOLD}"Logs for this span"${RESET}
       (or the "Logs" link). → the app's log lines for THIS request,
       filtered by trace_id, appear from Loki.

  ${BOLD}log → trace (closing the loop)${RESET}
    4. Explore → datasource ${BOLD}Loki${RESET} → query {service_name="app"}.
       Expand any line → click ${BOLD}"View trace"${RESET} on the trace_id field.

  ${BOLD}cross-service trace${RESET}
    5. Explore → ${BOLD}Tempo${RESET} → Search → service ${BOLD}worker${RESET}. Open a job
       trace: one tree spans app → rabbitmq → worker.
PIVOT
pause

step "Heal the slow app (optional)" "return latency to normal"
run "SLOW=0 $COMPOSE up -d app >/dev/null 2>&1 || true; echo 'SLOW reset'"

note "Explore, then tear down with:  make reset"
