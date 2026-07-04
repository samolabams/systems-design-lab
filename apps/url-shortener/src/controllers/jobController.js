'use strict';

/**
 * Job controller. Thin HTTP edge over jobService: returns 202 Accepted when the
 * job is queued, or 503 when the queue profile is not running — the app
 * contract (§4) requires the caller to know the work was not taken.
 */

const jobService = require('../services/jobService');

exports.enqueue = (req, res) => {
  if (!jobService.isReady()) {
    return res.status(503).json({ error: 'queue not available (start the async-queues profile)' });
  }
  jobService.enqueue(req.body || {});
  return res.status(202).json({ status: 'enqueued' });
};
