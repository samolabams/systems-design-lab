'use strict';

/**
 * Small cross-cutting helpers shared by controllers.
 */

const { SLOW, SLOW_MS } = require('./config');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Optional artificial latency (SLOW=1) used to demonstrate slow nodes in
// load balancing/observability. Controllers await this before doing work.
async function maybeSlow() {
  if (SLOW) await sleep(SLOW_MS);
}

module.exports = { sleep, maybeSlow };
