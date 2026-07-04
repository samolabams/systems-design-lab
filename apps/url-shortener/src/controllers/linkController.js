'use strict';

/**
 * Link controller (the "C" in MVC) — the HTTP edge of the URL-shortener's read
 * and write paths. Controllers are deliberately thin: they validate input,
 * delegate the actual work to the service, and shape the HTTP response. All the
 * orchestration (entity, repository, cache, retry) lives in
 * ../services/linkService.
 */

const linkService = require('../services/linkService');
const { log } = require('../logger');

// POST /shorten — write path; always the primary.
exports.shorten = async (req, res) => {
  const url = req.body && req.body.url;
  if (!url || typeof url !== 'string') {
    return res.status(400).json({ error: 'body must be { "url": "..." }' });
  }
  try {
    const link = await linkService.shorten(url);
    return res.status(201).json({ code: link.code });
  } catch (err) {
    if (err.code === 'ALLOC_FAILED') {
      return res.status(500).json({ error: 'could not allocate code' });
    }
    log({ event: 'shorten_error', error: err.message });
    return res.status(500).json({ error: 'internal error' });
  }
};

// GET /:code — read path; cache-aside in front of the replica (caching when active).
exports.redirect = async (req, res) => {
  try {
    const url = await linkService.resolve(req.params.code);
    if (!url) return res.status(404).json({ error: 'not found' });
    return res.redirect(302, url);
  } catch (err) {
    log({ event: 'lookup_error', error: err.message });
    return res.status(500).json({ error: 'internal error' });
  }
};
