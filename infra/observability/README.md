# infra/observability — seeing the system (metrics + traces + logs)

Reliable reasoning about a system requires visibility into its behavior. This
stack collects the three primary telemetry signals from every service and ties
them together in Grafana. It is enabled by `make observability`.

## What's here

- `prometheus/prometheus.yml` — scrape config. Uses DNS service discovery so it
  finds every `app` replica automatically, plus cAdvisor (containers) and the
  Postgres exporter (DB internals). Runs with `--enable-feature=exemplar-storage`
  so latency samples carry a `trace_id`.
- `tempo/tempo.yaml` — Grafana Tempo, the **traces** backend. Receives spans over
  OTLP and stores them on a local volume.
- `loki/loki-config.yaml` — Grafana Loki, the **logs** backend. Ingests logs over
  its native OTLP endpoint; indexes labels only, keeping the body + `trace_id` as
  structured metadata.
- `otel-collector/otel-collector-config.yaml` — the OpenTelemetry **Collector**.
  The app/worker speak one protocol (OTLP); the collector fans traces out to
  Tempo and logs to Loki. Replacing a backend requires only an exporter change in
  this collector configuration.
- `grafana/provisioning/` — auto-loaded datasources (Prometheus + Tempo + Loki)
  and the RED dashboard, plus the links that make the pivot work: exemplars →
  Tempo, trace span → Loki logs, log line → Tempo trace.

## The lesson

The three pillars are **metrics, traces, and logs**, and the point is not to
collect them but to **pivot between them** for one request:

```
metric spike (RED panel)  →  the exemplar's trace (Tempo)  →  that request's logs (Loki)
```

The app and worker are instrumented with OpenTelemetry (see their
`src/tracing.js`); context propagates across HTTP hops and *through the AMQP
message* to the worker, so `POST /jobs` is a single trace spanning
app → queue → worker. Pino stamps the active `trace_id` onto every log line,
which allows Grafana to navigate from trace to log and back.

**Why Tempo + Loki instead of Jaeger, Zipkin, or ELK?** Both are Grafana-native,
share a label vocabulary, and provide built-in correlation between signals. They
also store data on a local volume with a small index rather than requiring a
separate database backend. That small service
footprint matches the lab's goal of keeping each lesson focused. Because ingest
uses vendor-neutral OTLP, sending the same data to another backend would
require only a collector-exporter change.

**Used in:** observability (observability); availability reads the same metrics for its SLO panels.

