'use strict';

/**
 * Migration: create the `links` table.
 *
 * Migrations replace the old "create the table on boot" approach. Each
 * migration is a versioned, ordered change to the schema that Knex records in
 * the `knex_migrations` table, so the database knows which changes have already
 * run. This makes schema changes repeatable and reviewable, and lets the schema
 * evolve over time (a later migration could add a column or an index) without
 * anyone editing tables by hand.
 *
 * `up` applies the change; `down` reverses it (used by `knex migrate:rollback`).
 */

exports.up = async function up(knex) {
  await knex.schema.createTable('links', (table) => {
    table.text('code').primary();
    table.text('url').notNullable();
    table.timestamp('created_at', { useTz: true }).notNullable().defaultTo(knex.fn.now());
    table.index(['url'], 'links_url_idx');
  });
};

exports.down = async function down(knex) {
  await knex.schema.dropTableIfExists('links');
};
