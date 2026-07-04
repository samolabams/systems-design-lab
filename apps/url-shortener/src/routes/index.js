'use strict';

/**
 * Route table — maps URLs to controller actions (the app contract, §4).
 *
 *   GET  /health   -> healthController.health
 *   GET  /metrics  -> metricsController.metrics
 *   POST /shorten  -> linkController.shorten
 *   POST /jobs     -> jobController.enqueue
 *   GET  /:code    -> linkController.redirect
 *
 * The `/:code` catch-all is registered last so it does not shadow the named
 * routes above it.
 */

const express = require('express');
const healthController = require('../controllers/healthController');
const metricsController = require('../controllers/metricsController');
const linkController = require('../controllers/linkController');
const jobController = require('../controllers/jobController');

const router = express.Router();

router.get('/health', healthController.health);
router.get('/metrics', metricsController.metrics);
router.post('/shorten', linkController.shorten);
router.post('/jobs', jobController.enqueue);
router.get('/:code', linkController.redirect); // keep last

module.exports = router;
