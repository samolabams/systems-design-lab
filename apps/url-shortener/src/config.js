'use strict';

/**
 * Centralized configuration — every environment tunable in one place.
 *
 * Reading config once, here, keeps the rest of the codebase free of
 * `process.env` lookups (a 12-factor practice: config lives in the
 * environment, but the app reads it through a single typed surface).
 */

const os = require('os');

module.exports = {
  PORT: parseInt(process.env.PORT || '3000', 10),
  HOST: os.hostname(), // identifies which replica served a request (scaling)
  SLOW: process.env.SLOW === '1', // inject latency to demo slow nodes (load balancing)
  SLOW_MS: parseInt(process.env.SLOW_MS || '750', 10),
  DATABASE_URL: process.env.DATABASE_URL, // write path -> primary
  DATABASE_REPLICA_URL: process.env.DATABASE_REPLICA_URL || '', // read path -> replica (replication and failover)
  AMQP_URL: process.env.AMQP_URL || '', // async jobs -> RabbitMQ (async queues)
  REDIS_URL: process.env.REDIS_URL || '', // cache-aside store (caching); empty = cache off
  CACHE_TTL: parseInt(process.env.CACHE_TTL || '60', 10), // seconds a cached redirect lives
};
