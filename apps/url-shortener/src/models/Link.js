'use strict';

/**
 * Link entity (the "M" in MVC) — a plain class that represents one row of the
 * `links` table plus the domain logic that belongs to a link.
 *
 * The model holds *data and behaviour*, not database access. It knows what a
 * link is (a short `code` pointing at a `url`) and how to mint a new code, but
 * it does not know about Knex, pools, or SQL — that is the repository's job
 * (see ../repositories/linkRepository.js). Keeping the entity persistence-free
 * means the same class works whatever the storage is.
 */

// Short-code alphabet. Math.random is fine here: collisions are rare and the
// caller retries on the primary-key violation rather than pre-checking.
const ALPHABET = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

class Link {
  constructor({ code, url, createdAt = null }) {
    this.code = code;
    this.url = url;
    this.createdAt = createdAt;
  }

  // Generate a random short code.
  static makeCode(len = 7) {
    let out = '';
    for (let i = 0; i < len; i++) out += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    return out;
  }

  // Factory: a new link for the given URL with a freshly minted code.
  static forUrl(url) {
    return new Link({ code: Link.makeCode(), url });
  }

  // Rehydrate an entity from a database row (snake_case -> camelCase).
  static fromRow(row) {
    return new Link({ code: row.code, url: row.url, createdAt: row.created_at });
  }
}

module.exports = Link;
