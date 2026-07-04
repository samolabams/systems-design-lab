'use strict';

/**
 * OpenTelemetry bootstrap for the worker.
 *
 * Mirrors the app's src/tracing.js. Loaded before anything else so the amqplib
 * instrumentation can patch the consumer as it is required. Because context
 * rides the AMQP message, a job's trace here is a *child* of the app request
 * that enqueued it — so `POST /jobs` shows up as one trace spanning
 * app -> queue -> worker. Logs are stamped with the same trace_id and shipped
 * as OTLP to the collector, which forwards them to Loki.
 *
 * When the collector is absent (any profile without observability), OTLP
 * exports fail silently (OpenTelemetry's default diag logger is a no-op).
 */

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http');
const { BatchLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { AmqplibInstrumentation } = require('@opentelemetry/instrumentation-amqplib');
const { PinoInstrumentation } = require('@opentelemetry/instrumentation-pino');
const { OTEL_EXPORTER_OTLP_ENDPOINT } = require('./config');

const base = OTEL_EXPORTER_OTLP_ENDPOINT;

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: `${base}/v1/traces` }),
  logRecordProcessors: [
    new BatchLogRecordProcessor(new OTLPLogExporter({ url: `${base}/v1/logs` })),
  ],
  instrumentations: [
    new HttpInstrumentation(),
    new AmqplibInstrumentation(),
    new PinoInstrumentation(),
  ],
});

sdk.start();

process.on('SIGTERM', () => {
  sdk.shutdown().catch(() => {});
});
