'use strict';

/**
 * Prometheus metrics (RED method — Rate, Errors, Duration).
 *
 * Exposes a counter (request rate + errors by status) and a histogram
 * (duration, for percentiles). The middleware records both for every request
 * and also emits a structured access log. 5 scrapes `/metrics` and
 * graphs these.
 */

const client = require('prom-client');
const { trace } = require('@opentelemetry/api');
const { HOST } = require('./config');
const { log } = require('./logger');

const registry = new client.Registry();
// Serve OpenMetrics so histogram *exemplars* (a trace_id attached to a sample)
// are exposed; Prometheus stores them with --enable-feature=exemplar-storage and
// Grafana turns a latency spike into a one-click jump to that exact trace (observability).
registry.setContentType(client.openMetricsContentType);
registry.setDefaultLabels({ app: 'app', host: HOST });
client.collectDefaultMetrics({ register: registry }); // process/runtime gauges

const httpRequests = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [registry],
});

const httpDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  enableExemplars: true, // attach the active trace_id to each observation (observability)
  registers: [registry],
});

// Express middleware: time each request, record RED metrics, emit access log.
// Uses the matched route (e.g. `/:code`) as the label so cardinality stays low
// — labelling by raw path would create one series per short code.
function metricsMiddleware(req, res, next) {
  const start = process.hrtime.bigint();
  // Capture the trace id while the request context is still active; the finish
  // handler runs after the response, when the active span may be detached.
  const span = trace.getActiveSpan();
  const traceId = span ? span.spanContext().traceId : undefined;
  res.on('finish', () => {
    const seconds = Number(process.hrtime.bigint() - start) / 1e9;
    const route = req.route ? req.baseUrl + req.route.path : req.path;
    const labels = { method: req.method, route, status: String(res.statusCode) };
    httpRequests.inc(labels);
    // The exemplar links this latency sample to the trace that produced it.
    httpDuration.observe(
      traceId ? { labels, value: seconds, exemplarLabels: { trace_id: traceId } } : labels,
      traceId ? undefined : seconds
    );
    log({
      event: 'request',
      method: req.method,
      path: req.path,
      status: res.statusCode,
      ms: Math.round(seconds * 1000),
    });
  });
  next();
}

module.exports = { registry, metricsMiddleware };
