'use strict';

/**
 * RabbitMQ worker for async processing and backpressure — entrypoint.
 *
 * This file is deliberately thin, mirroring the app's server.js. It starts the
 * consumer and shuts it down cleanly on a signal; the moving parts live in
 * ./src, split by responsibility:
 *
 *   src/config.js   environment tunables (AMQP_URL, PREFETCH, WORK_MS)
 *   src/logger.js   structured logging (pino) to stdout
 *   src/queue.js    amqp-connection-manager consumer (connect, ack, drain)
 *   src/handler.js  the job logic — the part you customize
 *
 * Scale the worker count (not the buffer) to raise throughput:
 *   docker compose --profile async-queues up -d --scale worker=3
 */

// OpenTelemetry must load first so it can patch amqplib as it is required below.
// A job's trace links back to the app request that enqueued it.
require('./src/tracing');

const { log } = require('./src/logger');
const queue = require('./src/queue');
const { handle } = require('./src/handler');
const { SHUTDOWN_TIMEOUT_MS } = require('./src/config');

let shuttingDown = false;

queue.start(handle);

// Graceful shutdown: stop pulling new messages, let in-flight jobs ack, then
// close the connection. A message that is mid-flight when we exit is redelivered
// by RabbitMQ (at-least-once), so no work is lost.
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log({ event: 'shutdown_start', signal });

  // Force-exit if a job hangs (under Docker's ~10s stop grace period).
  const failsafe = setTimeout(() => {
    log({ event: 'shutdown_forced' });
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS);
  failsafe.unref();

  try {
    await queue.stopConsuming();
    await queue.drain();
    await queue.close();
    log({ event: 'shutdown_complete' });
    clearTimeout(failsafe);
    process.exit(0);
  } catch (err) {
    log({ event: 'shutdown_error', error: err.message });
    process.exit(1);
  }
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
