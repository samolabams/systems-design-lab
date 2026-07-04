'use strict';

/**
 * Health controller. Returns the container hostname so a demo can *visually
 * prove* which replica served a request (scaling) and so the load balancer's
 * healthcheck has an endpoint to probe (load balancing).
 */

const { HOST } = require('../config');

exports.health = (req, res) => {
  res.json({ host: HOST, role: 'app' });
};
