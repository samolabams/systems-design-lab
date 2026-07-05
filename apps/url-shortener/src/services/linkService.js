'use strict';

/**
 * Link service — the application logic of the URL-shortener.
 *
 * This is where the *actual work* lives, kept free of HTTP concerns so the
 * controller stays thin (parse request -> call service -> shape response). The
 * service orchestrates the domain entity (Link), the repository (storage), and
 * the cache (caching); the controller never touches those directly.
 */

const Link = require('../models/Link');
const linkRepository = require('../repositories/linkRepository');
const cache = require('../cache');
const { maybeSlow } = require('../util');

const cacheKey = (code) => `link:${code}`;
const MAX_URL_LENGTH = 2048;

function normalizeUrl(value) {
  if (!value || typeof value !== 'string') return null;
  if (value.length > MAX_URL_LENGTH) return null;
  try {
    const parsed = new URL(value.trim());
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return null;
    return parsed.toString();
  } catch {
    return null;
  }
}

/**
 * Create a short link for the given URL (write path; always the primary).
 *
 * Retries on the rare primary-key collision with a freshly minted code. On
 * success the new mapping is written through to the cache so the first redirect
 * is a hit. Throws an error tagged `code: 'ALLOC_FAILED'` if every attempt
 * collides, or rethrows an unexpected database error for the caller to handle.
 *
 * @param {string} url
 * @returns {Promise<{ link: Link, created: boolean }>} the persisted link and whether it was newly inserted
 */
async function shorten(url) {
  const normalizedUrl = normalizeUrl(url);
  if (!normalizedUrl) {
    const err = new Error('invalid url');
    err.code = 'INVALID_URL';
    throw err;
  }

  await maybeSlow();
  for (let attempt = 0; attempt < 5; attempt++) {
    const link = Link.forUrl(normalizedUrl);
    try {
      const { link: persisted, created } = await linkRepository.createOrFindByUrl(link);
      // Write-through of the new mapping. Links are immutable, so there is no
      // stale entry to invalidate.
      await cache.set(cacheKey(persisted.code), persisted.url);
      return { link: persisted, created };
    } catch (err) {
      if (err.code === '23505') {
        continue; // code collision -> try a new code
      }
      throw err; // unexpected error -> let the controller map it to a 500
    }
  }
  const err = new Error('could not allocate code');
  err.code = 'ALLOC_FAILED';
  throw err;
}

/**
 * Resolve a short code to its target URL (read path; cache-aside in front of
 * the replica, caching when active).
 *
 * @param {string} code
 * @returns {Promise<string|null>} the URL, or null if the code is unknown
 */
async function resolve(code) {
  if (!Link.isValidCode(code)) return null;
  await maybeSlow();
  // 1. Ask the cache first.
  const cached = await cache.get(cacheKey(code));
  if (cached) return cached;
  // 2. Miss -> read the database (replica when replication and failover active).
  const link = await linkRepository.findByCode(code);
  if (!link) return null;
  // 3. Populate the cache for next time, then return.
  await cache.set(cacheKey(code), link.url);
  return link.url;
}

module.exports = { shorten, resolve, normalizeUrl };
