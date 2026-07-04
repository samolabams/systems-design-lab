'use strict';

/**
 * Message queue client — RabbitMQ via AMQP.
 *
 * The broker may start *after* the app (the async-queues profile order) and can drop
 * mid-run, so the connection has to retry and re-establish its channel on its
 * own. Rather than hand-roll that loop, this module uses
 * `amqp-connection-manager`, which wraps `amqplib` and handles reconnection,
 * backoff, and channel re-setup. The small interface stays the same so callers
 * are unchanged:
 *   init()     — start connecting (returns immediately; connects in background)
 *   isReady()  — whether a publish can succeed right now
 *   publish()  — enqueue a durable message
 *   close()    — graceful shutdown (stops the auto-reconnect)
 *
 * The manager buffers publishes while disconnected, but the route still gates
 * on isReady() so an enqueue with no broker returns 503 immediately rather than
 * silently queueing in memory — that is the app contract (§4).
 */

const amqp = require('amqp-connection-manager');
const { AMQP_URL } = require('./config');
const { log } = require('./logger');

let connection = null;
let channelWrapper = null;

function init() {
  if (!AMQP_URL) return; // queue is optional; only the async-queues profile sets AMQP_URL

  // connect() returns immediately and keeps retrying in the background.
  connection = amqp.connect([AMQP_URL]);
  connection.on('connect', () => log({ event: 'amqp_connected' }));
  connection.on('disconnect', ({ err }) =>
    log({ event: 'amqp_disconnected', error: err && err.message })
  );

  // `setup` runs on every (re)connect, so the durable queue is always
  // re-asserted after the broker comes back. json:true serialises payloads.
  channelWrapper = connection.createChannel({
    json: true,
    setup: (channel) => channel.assertQueue('jobs', { durable: true }),
  });
}

function isReady() {
  return !!connection && connection.isConnected();
}

// Durable queue + persistent message so an enqueued job survives a broker
// restart. The route already returned 202, so a late failure is only logged.
// Callers must check isReady() first.
function publish(queue, payload) {
  channelWrapper
    .sendToQueue(queue, payload, { persistent: true })
    .catch((err) => log({ event: 'publish_error', error: err.message }));
}

async function close() {
  // Bound the close. When the app is shutting down while the broker was never
  // reachable (e.g. the base profile, where RabbitMQ is not running), the
  // connection manager is still in its reconnect loop and closing it can hang.
  // Race the close against a short timeout so it can never block shutdown — the
  // process exits straight after, so a still-pending close is harmless.
  const closing = (async () => {
    if (channelWrapper) await channelWrapper.close().catch(() => {});
    if (connection) await connection.close().catch(() => {});
  })();
  const timeout = new Promise((resolve) => setTimeout(resolve, 2000));
  await Promise.race([closing, timeout]);
}

module.exports = { init, isReady, publish, close };
