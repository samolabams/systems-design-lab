'use strict';

/**
 * Job handler — the part of the worker you actually customize.
 *
 * Everything else in this service is plumbing (connect, consume, ack, drain);
 * this file is the business logic. To make the worker do real work, change this
 * function. It receives the decoded message payload and returns when the job is
 * done; throwing causes the queue layer to nack-and-requeue (at-least-once).
 *
 * The demo just waits WORK_MS to simulate processing, which is enough to show
 * backpressure when you scale workers against a full queue (async queues).
 */

const { WORK_MS } = require('./config');
const { log } = require('./logger');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function handle(payload) {
  log({ event: 'job_start', payload });
  await sleep(WORK_MS); // simulate work — replace with the real task
  log({ event: 'job_done', payload });
}

module.exports = { handle };
