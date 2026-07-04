'use strict';

/**
 * Cache-aside client (8) — Redis via node-redis.
 *
 * The read path asks the cache first; on a miss it reads the database and
 * populates the cache (cache-aside, a.k.a. lazy loading). This is the most
 * common caching pattern: the application owns the cache logic, and the cache
 * only ever holds data that was actually requested.
 *
 * Failure is non-fatal by design. If REDIS_URL is empty (the base profile) or
 * Redis is unreachable, every call degrades to a no-op and the caller falls
 * through to the database — so the app behaves identically with the cache off,
 * just without the latency/offload win. A cache must never be a new single
 * point of failure for a read that the database can still serve.
 *
 * Hit/miss counts are exported as a Prometheus metric so 5 can graph the
 * cache hit ratio next to the RED panels.
 */

const { createClient } = require('redis');
const client = require('prom-client');
const { REDIS_URL, CACHE_TTL } = require('./config');
const { log } = require('./logger');
const { registry } = require('./metrics');

const cacheRequests = new client.Counter({
  name: 'cache_requests_total',
  help: 'Cache lookups by result',
  labelNames: ['result'], // hit | miss | disabled | error
  registers: [registry],
});

let redis = null;
let ready = false;

// init() — connect in the background (mirrors the queue client). Never throws;
// a down cache must not stop the app from booting.
function init() {
  if (!REDIS_URL) return; // cache disabled (base profile)
  redis = createClient({
    url: REDIS_URL,
    // Bounded backoff so a missing Redis (e.g. base profile) doesn't spin hot.
    socket: { reconnectStrategy: (retries) => Math.min(retries * 200, 5000) },
  });
  redis.on('ready', () => {
    ready = true;
    log({ event: 'cache_connected' });
  });
  redis.on('end', () => {
    ready = false;
  });
  // Swallow connection errors (logged once on first failure by the caller path).
  redis.on('error', () => {});
  redis.connect().catch((err) => log({ event: 'cache_connect_failed', error: err.message }));
}

function isEnabled() {
  return !!REDIS_URL;
}

// get(key) — returns the cached string, or null on miss/disabled/error.
async function get(key) {
  if (!ready) {
    cacheRequests.inc({ result: 'disabled' });
    return null;
  }
  try {
    const value = await redis.get(key);
    cacheRequests.inc({ result: value ? 'hit' : 'miss' });
    return value;
  } catch (err) {
    cacheRequests.inc({ result: 'error' });
    return null;
  }
}

// set(key, value, ttl) — populate with an expiry (TTL eviction).
async function set(key, value, ttlSeconds = CACHE_TTL) {
  if (!ready) return;
  try {
    await redis.set(key, value, { EX: ttlSeconds });
  } catch {
    /* cache writes are best-effort */
  }
}

// del(key) — explicit invalidation on write (the hard part of caching).
async function del(key) {
  if (!ready) return;
  try {
    await redis.del(key);
  } catch {
    /* best-effort */
  }
}

async function close() {
  if (redis) {
    try {
      await redis.quit();
    } catch {
      /* ignore */
    }
  }
}

module.exports = { init, isEnabled, get, set, del, close };
