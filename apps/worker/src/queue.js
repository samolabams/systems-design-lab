'use strict';

/**
 * Queue consumer — RabbitMQ via amqp-connection-manager.
 *
 * Uses the same library as the app's src/queue.js so both services connect the
 * same way: the manager reconnects and re-runs `setup` on every (re)connect, so
 * the durable queue and prefetch are always re-applied after a broker restart.
 *
 * Responsibilities:
 *   start(handle)    — connect and begin consuming, dispatching each job to the
 *                      handler; ack on success, nack-and-requeue on failure
 *   stopConsuming()  — cancel the consumer so no new jobs are delivered
 *   drain()          — wait for in-flight jobs to finish
 *   close()          — close the channel and connection
 *
 * Acknowledgement model: a message is acked only after the handler resolves, so
 * a worker that dies mid-job leaves the message unacked and RabbitMQ redelivers
 * it to another worker (at-least-once delivery).
 */

const amqp = require('amqp-connection-manager');
const { AMQP_URL, PREFETCH, QUEUE_NAME } = require('./config');
const { log } = require('./logger');

let connection = null;
let channelWrapper = null;
let consumerTag = null;
let inFlightCount = 0;

function start(handle) {
  if (channelWrapper) return;

  connection = amqp.connect([AMQP_URL]);
  connection.on('connect', () => log({ event: 'amqp_connected' }));
  connection.on('disconnect', ({ err }) =>
    log({ event: 'amqp_disconnected', error: err && err.message })
  );

  channelWrapper = connection.createChannel({
    setup: async (channel) => {
      await channel.assertQueue(QUEUE_NAME, { durable: true });
      await channel.prefetch(PREFETCH); // one unacked message per worker
      const consumer = await channel.consume(QUEUE_NAME, (msg) => processMessage(channel, msg, handle));
      consumerTag = consumer.consumerTag;
      log({ event: 'consuming', queue: QUEUE_NAME, prefetch: PREFETCH });
    },
  });
}

async function processMessage(channel, msg, handle) {
  if (!msg) return;

  inFlightCount++;
  try {
    const payload = parsePayload(msg);
    await handle(payload);
    channel.ack(msg);
  } catch (err) {
    if (err.code === 'INVALID_JSON') {
      log({ event: 'job_invalid_json', raw: msg.content.toString() });
      channel.nack(msg, false, false);
    } else {
      log({ event: 'job_error', error: err.message });
      channel.nack(msg, false, true); // requeue for another attempt
    }
  } finally {
    inFlightCount--;
  }
}

function parsePayload(msg) {
  try {
    return JSON.parse(msg.content.toString() || '{}');
  } catch (error) {
    error.code = 'INVALID_JSON';
    throw error;
  }
}

// Stop pulling new messages (cancel the consumer) so in-flight jobs can finish
// before the connection closes. The caller then waits on drain().
async function stopConsuming() {
  if (channelWrapper && consumerTag) {
    await channelWrapper.cancel(consumerTag).catch(() => {});
    consumerTag = null;
  }
}

async function drain(intervalMs = 50) {
  while (inFlightCount > 0) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}

async function close() {
  if (channelWrapper) await channelWrapper.close().catch(() => {});
  if (connection) await connection.close().catch(() => {});
  channelWrapper = null;
  connection = null;
}

module.exports = { start, stopConsuming, drain, close };
