'use strict';

/**
 * Metrics controller. Exposes the Prometheus registry in the text exposition
 * format that 5's Prometheus scrapes.
 */

const { registry } = require('../metrics');

exports.metrics = async (req, res) => {
  res.set('Content-Type', registry.contentType);
  res.end(await registry.metrics());
};
