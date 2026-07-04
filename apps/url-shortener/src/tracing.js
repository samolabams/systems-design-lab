'use strict';

/**
 * OpenTelemetry bootstrap — the app's third-pillar wiring (5).
 *
 * This file is loaded BEFORE any other module (see server.js's first line) so
 * the instrumentations can monkey-patch `http`, `express`, `pg`, and `amqplib`
 * as they are required. It does two things:
 *
 *   1. Traces — every HTTP request, DB query, and AMQP publish becomes a span.
 *      Context propagates automatically: a span-id rides the AMQP message to the
 *      worker, and the W3C `traceparent` header across HTTP hops, so one request
 *      is a single trace across services.
 *   2. Log correlation — the pino instrumentation stamps `trace_id`/`span_id`
 *      onto every log line and forwards those lines to the collector as OTLP
 *      logs, which is what lets Grafana pivot trace -> log for one request.
 *
 * Everything is exported as OTLP to the collector (OTEL_EXPORTER_OTLP_ENDPOINT).
 * The collector only runs under the observability profile; in every other
 * profile the export simply fails and is dropped (OpenTelemetry's default
 * diagnostic logger is a no-op), so the app is never affected by its absence.
 * Instrumentation is a property of the app; the *backends* are what observability turns on.
 */

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { ExpressInstrumentation } = require('@opentelemetry/instrumentation-express');
const { PgInstrumentation } = require('@opentelemetry/instrumentation-pg');
const { AmqplibInstrumentation } = require('@opentelemetry/instrumentation-amqplib');
const { PinoInstrumentation } = require('@opentelemetry/instrumentation-pino');

// Endpoint + service name come from OTEL_* env (set in docker-compose). The
// OTLP exporters read OTEL_EXPORTER_OTLP_ENDPOINT on their own; we only append
// the signal-specific path.
const base = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector:4318';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: `${base}/v1/traces` }),
  logRecordProcessors: [
    new BatchLogRecordProcessor(new OTLPLogExporter({ url: `${base}/v1/logs` })),
  ],
  instrumentations: [
    new HttpInstrumentation(),
    new ExpressInstrumentation(),
    new PgInstrumentation(),
    new AmqplibInstrumentation(),
    // Correlate logs with the active span and ship them as OTLP log records.
    new PinoInstrumentation(),
  ],
});

sdk.start();

process.on('SIGTERM', () => {
  sdk.shutdown().catch(() => {});
});
