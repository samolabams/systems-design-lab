'use strict';

/**
 * Knex configuration for the migration CLI.
 *
 * The Knex command-line tool reads this file to know how to connect and where
 * the migration files live, e.g.:
 *   npx knex migrate:make add_clicks_column   # scaffold a new migration
 *   npx knex migrate:latest                   # apply pending migrations
 *   npx knex migrate:rollback                 # undo the last batch
 *
 * Migrations always run against the primary (DATABASE_URL); the replica
 * receives the schema change through replication (2). The app also runs
 * `migrate.latest()` on boot (see src/db.js), so this file mainly exists for
 * authoring and ad-hoc CLI use.
 */

module.exports = {
  client: 'pg',
  connection: process.env.DATABASE_URL,
  migrations: {
    directory: './migrations',
  },
};
