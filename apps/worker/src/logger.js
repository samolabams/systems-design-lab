'use strict';

/**
 * Structured logging with pino — same shape as the app's src/logger.js so logs
 * from the app and worker line up in the same collector (5). Every line
 * carries `host` and `role: 'worker'`, plus an ISO `ts`.
 */

const pino = require('pino');
const { HOST } = require('./config');

const logger = pino({
  base: { host: HOST, role: 'worker' },
  timestamp: () => `,"ts":"${new Date().toISOString()}"`,
  formatters: {
    level: (label) => ({ level: label }),
  },
});

// Pass the event name as pino's message so the OTLP log body (the Loki line) is
// non-empty; the object fields ride along as structured metadata.
function log(fields) {
  logger.info(fields, fields && fields.event);
}

module.exports = { logger, log };
