'use strict';

/**
 * Link repository — the only place that talks to the database for links.
 *
 * The repository pattern separates *what* the data is (the Link entity) from
 * *how* it is stored and retrieved (here). It exposes a collection-like
 * interface — insert, findByCode — and hides Knex, SQL, and the read/write
 * split behind it:
 *   - writes always go to the primary (writeDb)
 *   - reads go to a replica when configured (readDb), otherwise the primary
 * (2). Centralising that split here means controllers never have to know
 * which pool to use, and swapping the storage engine touches only this file.
 */

const { writeDb, readDb } = require('../db');
const Link = require('../models/Link');

// Persist a new link on the primary. Throws on a duplicate code (Postgres
// error 23505, unique_violation), which the caller catches to retry.
async function insert(link) {
  await writeDb('links').insert({ code: link.code, url: link.url });
}

// Look up a link by its code on the replica. Returns a Link entity or null.
async function findByCode(code) {
  const row = await readDb('links').where({ code }).first('code', 'url', 'created_at');
  return row ? Link.fromRow(row) : null;
}

module.exports = { insert, findByCode };
