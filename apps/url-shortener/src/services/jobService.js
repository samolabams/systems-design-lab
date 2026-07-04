'use strict';

/**
 * Job service — the application logic for enqueuing background work.
 *
 * Keeps the queue interaction out of the controller so the HTTP handler stays
 * thin. The queue client (RabbitMQ via amqp-connection-manager) is owned by
 * ../queue; this service is the boundary the controller calls.
 */

const queue = require('../queue');

// Whether the queue is connected and ready to accept work (false on the base
// profile, where the async queue is not running).
function isReady() {
  return queue.isReady();
}

// Publish a job onto the `jobs` queue. Caller should check isReady() first.
function enqueue(payload) {
  queue.publish('jobs', payload || {});
}

module.exports = { isReady, enqueue };
