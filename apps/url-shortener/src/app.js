'use strict';

/**
 * Express application assembly.
 *
 * This file wires middleware to routes and nothing else — no network, no
 * process signals. Keeping the app a pure object (created here, listened on in
 * server.js) is what makes it testable: a test can `require('./src/app')` and
 * drive it with supertest without opening a port.
 *
 * Middleware order matters:
 *   1. express.json()      parse JSON bodies before handlers read req.body
 *   2. metricsMiddleware   time every request (RED metrics) and emit access logs
 *   3. routes              the actual endpoints
 */

const express = require('express');
const { metricsMiddleware } = require('./metrics');
const routes = require('./routes');

const app = express();
app.use(express.json());
app.use(metricsMiddleware);

app.use(routes);

module.exports = app;
