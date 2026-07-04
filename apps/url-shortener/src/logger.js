'use strict';

/**
 * Structured logging with pino — one JSON object per line to stdout.
 *
 * Twelve-factor apps treat logs as an event stream and never manage log files
 * themselves — they write to stdout and let the platform (Docker, then
 * Prometheus/Loki in observability) collect it. We use pino because it is the de-facto
 * standard structured logger for Node and is fast (it serialises JSON directly
 * rather than building intermediate objects).
 *
 * We keep a tiny `log({ event, ... })` facade so the rest of the codebase logs
 * the same way regardless of the backend, and we shape pino's output to match
 * the lab's convention: a top-level `ts` (ISO timestamp) and `host` on every
 * line, instead of pino's default epoch `time`/`pid`.
 */

const pino = require('pino');
const { HOST } = require('./config');

const logger = pino({
  base: { host: HOST }, // on every line; replaces pino's default pid/hostname
  timestamp: () => `,"ts":"${new Date().toISOString()}"`,
  formatters: {
    level: (label) => ({ level: label }), // log the name ("info") not the number
  },
});

// Facade: existing callers do `log({ event: 'request', ... })`. We pass the
// event name as pino's message string so it becomes the OTLP log *body* — that
// is what shows up as the log line in Loki (the fields ride along as structured
// metadata). Without a message the exported body is empty and the line is blank.
function log(fields) {
  logger.info(fields, fields && fields.event);
}

module.exports = { logger, log };
