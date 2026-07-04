'use strict';

/**
 * Centralized configuration — every environment tunable in one place, mirroring
 * the app's src/config.js so the two services read config the same way.
 */

const os = require('os');

function parseIntegerInRange(name, rawValue, defaultValue, min) {
  const value = Number(rawValue === undefined ? defaultValue : rawValue);
  if (!Number.isInteger(value) || value < min) {
    throw new Error(`${name} must be an integer greater than or equal to ${min}`);
  }
  return value;
}

module.exports = {
  HOST: os.hostname(), // identifies which worker replica processed a job (async queues scaling)
  AMQP_URL: process.env.AMQP_URL || 'amqp://app:app@rabbitmq:5672',
  QUEUE_NAME: process.env.QUEUE_NAME || 'jobs',
  // prefetch(1) means one unacked message per worker, so adding workers (not a
  // bigger buffer) is what raises throughput — the backpressure lesson (async queues).
  PREFETCH: parseIntegerInRange('PREFETCH', process.env.PREFETCH, 1, 1),
  WORK_MS: parseIntegerInRange('WORK_MS', process.env.WORK_MS, 500, 0), // simulated work per job
  SHUTDOWN_TIMEOUT_MS: parseIntegerInRange('SHUTDOWN_TIMEOUT_MS', process.env.SHUTDOWN_TIMEOUT_MS, 8000, 1),
  OTEL_EXPORTER_OTLP_ENDPOINT: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector:4318',
};
