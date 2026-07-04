'use strict';

/**
 * Database access — the read/write split (2).
 *
 * Writes always go to the primary; reads go to a replica when
 * DATABASE_REPLICA_URL is set, otherwise they fall back to the primary. This is
 * the textbook way to scale reads: the primary stays the single source of
 * truth, and read load spreads across followers (at the cost of replication
 * lag — the read-after-write hazard explored in replication and failover/consistency models).
 *
 * We use Knex (a SQL query builder) for two things: connection pooling and
 * composing queries without hand-writing SQL strings in the models. Each Knex
 * instance owns its own pool, capped by `pool.max` so the app tier cannot
 * exhaust Postgres's backends as it scales out (scaling). PgBouncer adds a second
 * pooling layer in front of the database.
 */

const knex = require('knex');
const path = require('path');
const { DATABASE_URL, DATABASE_REPLICA_URL } = require('./config');
const { log } = require('./logger');

function makePool(connectionString) {
  return knex({
    client: 'pg',
    connection: connectionString,
    pool: { min: 0, max: 10 },
    // Migration files live alongside the app code, one level up from src/.
    migrations: { directory: path.join(__dirname, '..', 'migrations') },
  });
}

const writeDb = makePool(DATABASE_URL);
const readDb = DATABASE_REPLICA_URL ? makePool(DATABASE_REPLICA_URL) : writeDb;

// Apply any pending migrations on boot. Migrations run against the primary; the
// replica receives the schema change via replication (2).
//
// Knex serialises concurrent runs with a lock table (knex_migrations_lock), so
// when several app replicas boot at once (scaling) only one applies the migration
// and the rest see it as already done. If a replica loses that race it throws a
// "lock" error — harmless here, because the winner has applied the schema — so
// we log and continue. In production you would instead run migrations as a
// separate one-shot step before rolling out the app.
async function runMigrations() {
  try {
    const [, applied] = await writeDb.migrate.latest();
    log({ event: 'migrations_applied', count: applied.length, files: applied });
  } catch (err) {
    if (/lock/i.test(err.message)) {
      log({ event: 'migrations_locked', note: 'another instance is migrating' });
      return;
    }
    throw err;
  }
}

// Release both pools on shutdown so Postgres reclaims the connections promptly.
async function closePools() {
  await writeDb.destroy().catch(() => {});
  if (readDb !== writeDb) await readDb.destroy().catch(() => {});
}

module.exports = { writeDb, readDb, runMigrations, closePools };
