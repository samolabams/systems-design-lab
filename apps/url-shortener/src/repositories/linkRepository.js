'use strict';

/**
 * Link repository — the only place that talks to the database for links.
 *
 * The repository pattern separates *what* the data is (the Link entity) from
 * *how* it is stored and retrieved (here). It exposes a collection-like
 * interface — createOrFindByUrl, findByCode — and hides Knex, SQL, and the read/write
 * split behind it:
 *   - writes always go to the primary (writeDb)
 *   - reads go to a replica when configured (readDb), otherwise the primary
 * (2). Centralising that split here means controllers never have to know
 * which pool to use, and swapping the storage engine touches only this file.
 */

const { writeDb, readDb } = require('../db');
const Link = require('../models/Link');

async function createOrFindByUrl(link) {
  return writeDb.transaction(async (trx) => {
    await trx.raw('SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', [link.url]);
    const existing = await trx('links')
      .where({ url: link.url })
      .orderBy('created_at', 'asc')
      .orderBy('code', 'asc')
      .first('code', 'url', 'created_at');
    if (existing) return { link: Link.fromRow(existing), created: false };

    await trx('links').insert({ code: link.code, url: link.url });
    return { link, created: true };
  });
}

// Look up a link by its code on the replica. Returns a Link entity or null.
async function findByCode(code) {
  const row = await readDb('links').where({ code }).first('code', 'url', 'created_at');
  return row ? Link.fromRow(row) : null;
}

module.exports = { createOrFindByUrl, findByCode };
