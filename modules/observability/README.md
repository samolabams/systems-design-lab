# Observability: metrics, logs & traces

**Track:** Components
**Prerequisites:** none for metrics and logs; the cross-service trace walkthrough
also starts the queue/worker path from [async queues](../async-queues/README.md).

## Outcome

After this module, you should understand observability as a method
for answering operational questions with evidence. You should be able to
explain:

1. What metrics, logs, and traces each show.
2. How RED and USE metrics answer different questions.
3. What a trace, span, trace ID, exemplar, and structured log are.
4. How OpenTelemetry carries context through HTTP and asynchronous work.
5. How to pivot from a metric spike to one trace and then to correlated logs.
6. Why high-cardinality data belongs in traces/logs instead of metric labels.

## What you will build or run

1. A local observability stack with Prometheus, Grafana, Tempo, Loki, and the collector.
2. Requests that generate metrics, traces, and structured logs from the gateway, app, and worker.
3. A metric-to-trace-to-log investigation that connects a symptom to one request path.
4. Cardinality and label examples that show what belongs in metrics versus traces or logs.

## Why this matters

Reliable operation and reasoning require visibility into system behavior. Other
modules make claims such as "p95 drops with more replicas" and "lag grows under
load"; observability provides the measurements that verify those claims.
Observability turns a vague report such as "the system is slow" into a specific
statement such as "p99 latency on the read path tripled after a replica was
removed."

## Concept

Observability is the ability to understand a system's internal behavior from the
signals it emits. It commonly rests on **three signals**: metrics, traces, and
logs. A metric shows that behavior changed, a trace shows the request path, and
logs provide detailed events from services on that path.

- **Metrics** — low-cost, aggregated numbers sampled over time. `prometheus` scrapes
  the app's `/metrics` for RED (**R**ate, **E**rrors, **D**uration — the three
  externally visible request behavior), `cadvisor` for container USE (CPU, memory, IO — how
  hard the machine is working), and `postgres-exporter` for DB internals.
  `grafana` graphs them all.
- **Traces** — a way to follow one request as it hops between services. The whole
  journey of a single request is a **trace**, and each step inside it — a DB
  query, an HTTP call — is a **span**. The app and worker emit these using
  **OpenTelemetry**, an open standard for producing telemetry. Spans travel as
  **OTLP** (OpenTelemetry's wire format) to the **collector**, which forwards
  them to **Tempo**, where traces are stored.
  Crucially, the trace follows the request across HTTP calls and even through the
  RabbitMQ message it publishes, so a gateway request to `POST /api/jobs` maps to
  the app's internal `POST /jobs` route and shows up as one trace spanning app →
  RabbitMQ → worker.
- **Logs** — the app's structured stdout is tagged with the current `trace_id` by
  pino, then shipped over OTLP to the collector and on to **Loki**, the log store.

The payoff is the **pivot** — hopping between all three pillars for a single
request:

```
metric spike (Duration panel exemplar) → the exact trace (Tempo) → that request's logs (Loki) → back to the trace
```

That first hop works because of an **exemplar**: a single sampled point attached
to a metric that remembers the `trace_id` behind it. It is the clickable bridge
from a spike on a graph to the one request that caused it.

The metrics come in two flavours worth naming. **RED** (Rate, Errors, Duration)
looks at the service from the outside — how are requests going? **USE**
(Utilization, Saturation, Errors) looks at the machine from the inside — how hard
is the hardware working?

## How it works

Prometheus uses DNS service discovery, so it finds every `app` replica
automatically without additional scrape configuration and runs with `exemplar-storage` on, so
each latency histogram sample carries the `trace_id` that produced it. Grafana is
provisioned from code (datasources + dashboards in
`infra/observability/grafana/provisioning/`), including three correlation links:
an exemplar → Tempo, a trace span → its Loki logs, and a Loki log line → its
Tempo trace. The app increments `http_requests_total` and observes a
request-duration histogram (attaching the exemplar), which is what makes the
rate/error/percentile panels — and the one-click jump to a trace — possible.

Because logs ship over OTLP, each pino field (`trace_id`, `event`, …) arrives in
Loki as **structured metadata**, while the log *body* is the event name
(`request`, `job_start`, `job_done`). So the trace → log link filters on metadata
with `{service_name=~".+"} | trace_id="<id>"` — a `|=` line filter would miss it,
because the id is not in the body. The `=~".+"` selector spans **app and worker**,
so a cross-service job trace surfaces every service's logs in one query.

The app and worker are **always** instrumented
([apps/url-shortener/src/tracing.js](../../apps/url-shortener/src/tracing.js) and
[apps/worker/src/tracing.js](../../apps/worker/src/tracing.js)); this profile
enables the backends. In every other profile the OTLP export target is absent,
so spans/logs are dropped silently — OpenTelemetry's default diagnostic logger is
a no-op — and the app is unaffected.

## Run

```bash
pwd
make observability
# Grafana:  http://localhost:3001   (anonymous viewer; admin/admin)
# Tempo + Loki + Prometheus are backend-only — reach them through Grafana.

# Guided metric -> trace -> log walkthrough (brings up the queue/worker too):
./modules/observability/demo.sh
```

The output of `pwd` should end with `systems-design`.

`make observability` starts the observability backends. The guided demo also
brings up the async queue profile so `POST /api/jobs` can produce a trace that
spans the app, broker, and worker. Without the queue path, the metrics dashboard
still works, but the cross-service trace is incomplete.

Open the provisioned **"RED — gateway → app → DB"** dashboard and observe rate,
5xx, and p50/p95/p99 move under load; the diamonds on the Duration panel are
exemplars — click one to jump to its trace.

## How to read the commands

The demo brings up observability backends plus the queue profile so both
synchronous and asynchronous request paths are visible. Read traffic-generation
commands as probes that create telemetry:

| Command shape | Telemetry it should create |
|---|---|
| `GET /health` | request metric, trace, structured log |
| `POST /shorten` | app and database spans |
| `POST /api/jobs` | app, RabbitMQ, and worker spans |
| `SLOW=1 ... app` | visible latency spike and exemplar |

## How to read the output

Prometheus numbers prove metrics are flowing. Tempo search results prove traces
are stored. Loki query results prove logs carry trace metadata. The important
workflow is the pivot:

```text
metric spike -> exemplar trace_id -> Tempo trace -> Loki logs
```

If a job trace includes both app and worker spans, context propagation through
the queue is working.

## What to observe

1. **Rate** rises with k6 VUs; **Duration** p95 climbs as you remove replicas.
2. Flip `SLOW=1` on the app and find the latency spike in the Duration panel,
   then click its **exemplar** → the exact slow **trace** in Tempo → its **logs**
   in Loki. One request, three views.
3. `POST /api/jobs` in Tempo is a single trace across app → queue → worker — proof
   that context propagated through the message broker.
4. `cadvisor` shows which container is CPU-bound; `postgres-exporter` shows
   connection counts and tuple activity — the USE side of the picture.

## What you learned

- Observability is how a system explains what it is doing from the outside.
- Metrics, logs, and traces answer different debugging questions.
- Labels and high-cardinality fields must be chosen carefully.
- Dashboards are useful when they connect user symptoms to component behavior.

## Practice experiments

1. Generate read traffic and identify the RED panels that move.
2. Enable `SLOW=1`, then find one exemplar and follow it to a trace.
3. Open a worker trace and verify its logs share the same trace ID.
4. Decide which field should not become a Prometheus label because of high
  cardinality.

## Trade-offs

- **RED vs USE** — reach for RED when answering "are users affected?", USE when
  answering "what resource is saturated?". Most investigations require both.
- **Metrics vs traces** — metrics are low-cost but *aggregate*; they indicate
  that something is slow. Traces are per-request and more expensive to store, so
  production systems usually **sample** them. This lab keeps 100% sampling
  because the volume is small.
- **Tempo/Loki vs Jaeger/Zipkin/ELK** — Tempo and Loki are Grafana-native (one
  UI, shared labels, correlation built in) and store to a local volume with a
  small index, rather than a separate large database cluster. Because ingest
  is vendor-neutral OTLP, switching backends is a collector-exporter change, not
  an app change.
- High-cardinality labels (per-user, per-URL) can blow up Prometheus memory —
  keep label sets small; that is why per-request identity lives in *traces/logs*,
  not metric labels.

## Next steps

- [Availability](../availability/README.md) for reliability targets.
- [Circuit breakers](../circuit-breakers/README.md) for failure signals.
- [Async queues](../async-queues/README.md) for observing background work.

## Further reading

- Tom Wilkie, "The RED Method": https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/
- Brendan Gregg, "The USE Method": https://www.brendangregg.com/usemethod.html
- OpenTelemetry, "What is OpenTelemetry?": https://opentelemetry.io/docs/what-is-opentelemetry/
- Grafana, "Tempo" (traces) & "Loki" (logs): https://grafana.com/docs/tempo/latest/ · https://grafana.com/docs/loki/latest/
- Google SRE Book — "Monitoring Distributed Systems" (the four golden signals):
  https://sre.google/sre-book/monitoring-distributed-systems/

## Cleanup

```bash
make reset
```
