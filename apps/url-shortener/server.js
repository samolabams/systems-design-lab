'use strict';

/**
 * Reference URL-shortener app for the Systems Design Lab — process entrypoint.
 *
 * This file is deliberately thin. Its only jobs are to (1) start dependencies,
 * (2) open the HTTP port, and (3) shut everything down cleanly on a signal.
 * The application itself lives in ./src, organised MVC-style:
 *
 *   src/config.js        environment + derived constants (12-factor)
 *   src/logger.js        structured logging (pino) to stdout
 *   src/metrics.js       Prometheus registry + per-request RED middleware
 *   src/db.js            Knex pools (write->primary, read->replica) + schema
 *   src/queue.js         optional AMQP client with reconnect (4)
 *   src/cache.js         optional Redis cache-aside client (8)
 *   src/util.js          small shared helpers (maybeSlow)
 *   src/models/          domain entities (the "M") — Link (data + behaviour)
 *   src/repositories/    database access — linkRepository (all SQL lives here)
 *   src/controllers/     request handlers (the "C") — health/metrics/link/job
 *   src/routes/          URL -> controller table
 *   src/app.js           Express assembly (middleware + routes)
 *
 * Suggested reading order: config -> logger -> metrics -> db -> queue ->
 * models -> repositories -> controllers -> routes -> app -> this file.
 */

// OpenTelemetry must load first so it can patch http/express/pg/amqplib as they
// are required below (5 — traces & log correlation).
require('./src/tracing');

const { createHttpTerminator } = require('http-terminator');
const { PORT, SLOW, DATABASE_REPLICA_URL } = require('./src/config');
const { log } = require('./src/logger');
const app = require('./src/app');
const db = require('./src/db');
const queue = require('./src/queue');
const cache = require('./src/cache');

let server = null;
let httpTerminator = null;
let shuttingDown = false;

async function start() {
  // Apply pending migrations on the primary; the replica gets them via
  // replication. Failing here is fatal — the app cannot serve without a schema.
  await db.runMigrations();
  queue.init(); // non-blocking: amqp-connection-manager connects in the background
  cache.init(); // non-blocking: Redis connects in the background (caching); no-op if off
  server = app.listen(PORT, () =>
    log({ event: 'listening', port: PORT, slow: SLOW, replica: !!DATABASE_REPLICA_URL })
  );
  // http-terminator drains keep-alive connections too, which a plain
  // server.close() leaves hanging.
  httpTerminator = createHttpTerminator({ server });
}

// Graceful shutdown: stop accepting new connections, then release resources.
// Docker sends SIGTERM on `stop`/scale-down; draining here avoids dropped
// in-flight requests and leaked DB/broker connections on every deploy.
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log({ event: 'shutdown_start', signal });

  // Force-exit if a hung connection prevents a clean close (under Docker's
  // default 10s stop grace period, so the graceful path wins normally).
  const failsafe = setTimeout(() => {
    log({ event: 'shutdown_forced' });
    process.exit(1);
  }, 8000);
  failsafe.unref();

  try {
    if (httpTerminator) await httpTerminator.terminate();
    log({ event: 'shutdown_http_closed' });
    await queue.close();
    log({ event: 'shutdown_queue_closed' });
    await cache.close();
    await db.closePools();
    log({ event: 'shutdown_db_closed' });
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

start();
