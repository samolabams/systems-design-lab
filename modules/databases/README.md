# Databases

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand a database as a concrete
system component rather than an abstract placeholder labeled "storage." With no
prior database knowledge, you should be able to explain:

1. What a database does for an application.
2. Why stateful data is harder to scale than stateless app replicas.
3. The difference between tables, rows, columns, documents, and keys.
4. Why indexes matter for read performance.
5. What transactions protect.
6. What SQL and NoSQL mean in system design conversations.
7. Why replication, sharding, caching, and queues come later as responses to measured limits.

## What you will build or run

1. A running database-backed request path through the reference app.
2. Commands that inspect writes, reads, schema, and durable state.
3. A comparison between structured records and other storage patterns.
4. A practical view of where the database fits in a larger system.

## Why this matters

Most systems eventually need to remember something: users, orders, messages, payments, URLs, sessions, inventory, or audit history. That durable memory usually lives in a database.

A stateless app replica can be replaced freely because it does not own unique data. A database is different. It is the source of truth for data that must survive restarts and failures. That is why scaling the app tier in scaling is easier than scaling the database tier: app replicas are mostly interchangeable, but the database must protect correctness.

A URL shortener stores link mappings in a durable data store:

```text
code -> original URL
```

A request to create a short link writes a mapping. A request to resolve a short
code reads that mapping. The lab uses Postgres for the runnable example, but the
design ideas apply to relational databases, document stores, key-value stores,
and other database families. Everything later in the data path builds on this
foundation:

- Database scaling: decide which pressure you are solving before adding mechanisms.
- Replication and failover: make database data available on another node.
- Leader election: choose a new write leader automatically when one fails.
- Partitioning and sharding: split data across nodes when one database is no longer enough.
- Caching: avoid repeating hot database reads.
- Async queues: protect the database from bursts by moving work out of the request path.

## Concept

A database is a system that stores data and lets applications retrieve or change
it safely. Databases are usually classified by **data model**: the structure they
use to represent data and the operations they optimize for.

| Model | Shape | Good fit | Common trade-off |
|---|---|---|---|
| Relational / SQL | tables, rows, columns | structured data, joins, transactions | scaling writes across many nodes is harder |
| Document | JSON-like documents | nested objects read together | joins and cross-document rules are weaker |
| Key-value | key -> value | fast point lookups, caches, sessions | limited querying |
| Wide-column | rows partitioned by key, flexible columns | huge write volume, time-series/event-like data | query patterns must be planned early |
| Vector store / vector index | embedding vectors | semantic similarity, recommendations, similar-item search | approximate lookup and embedding lifecycle |
| Object storage | blobs/files | images, videos, backups, large objects | not for row-level transactions |

This module stays product-neutral in the concept section. The runnable lab uses
Postgres because the base app already depends on it and because a relational
database makes schema, indexes, and transactions easy to inspect. That does not
mean every system should use Postgres.

## Vocabulary

- **Table** - a named collection of rows, like `links`.
- **Row** - one stored record, like one short-code mapping.
- **Column** - one field in every row, like `code`, `url`, or `created_at`.
- **Primary key** - the identifier for a row. In the runnable lab, `links.code` is the primary key.
- **Index** - a data structure that helps the database find rows without scanning the whole table.
- **Embedding** - a numeric vector that represents the meaning or features of
  text, an image, or another input.
- **Vector store** - a database or index optimized for finding nearby embedding
  vectors.
- **Query** - a request to read or change data.
- **Transaction** - a group of database changes that commit together or roll back together.
- **Schema** - the structure of the data: tables, columns, constraints, and indexes.
- **Migration** - a versioned schema change applied in order.
- **Source of truth** - the place the system trusts as the durable record.

## Lab implementation

The generic ideas above become concrete in the base stack:

```text
app -> PgBouncer -> Postgres primary
```

The app talks to PgBouncer, a connection pooler. PgBouncer talks to the Postgres primary. The database itself is not exposed directly to your host browser; it is on the internal Docker network.

The app migration creates one table:

```text
links
- code       primary key
- url        original URL
- created_at timestamp
```

That small table is enough to demonstrate database fundamentals without turning
the module into a Postgres-only lesson.

## Run

```bash
make base
./modules/databases/demo.sh
```

The demo is interactive by default. To run it without pauses:

```bash
AUTO=1 ./modules/databases/demo.sh
```

## How to read the commands

Most demo commands use `psql`, the Postgres command-line client. Treat this as
the tool for inspecting the lab implementation, not as a claim that every design
must choose Postgres:

```bash
docker compose exec -T postgres-primary psql -U app -d app -c "SELECT count(*) FROM links;"
```

Read that as:

| Part | Meaning |
|---|---|
| `docker compose exec -T postgres-primary` | run a command inside the Postgres container |
| `psql` | open the Postgres client |
| `-U app` | connect as user `app` |
| `-d app` | connect to database `app` |
| `-c "..."` | run this SQL command and exit |

The SQL examples show general relational ideas: inspect schema, insert a row,
read it back, view indexes, and roll back a transaction. Another database family
would expose different commands, but the design questions would be the same:
what data shape is stored, how it is queried, what correctness guarantees it
needs, and how it behaves under scale.

## How to read the output

Table descriptions show schema: column names, types, indexes, and constraints.
`INSERT` output proves a row was written. `SELECT` output proves durable data can
be read later. `ROLLBACK` followed by a missing row proves a transaction can undo
uncommitted work.

## What to observe

1. **Schema** - the `links` table has explicit columns and a primary key.
2. **Rows** - inserting a link creates durable data that can be read later.
3. **Primary key lookup** - fetching by `code` matches the app's redirect path.
4. **Indexes** - the primary key creates an index the database can use for lookup.
5. **Transactions** - a row inserted inside a transaction disappears after `ROLLBACK`.
6. **Model choice** - the same idea could be represented as a SQL row, a JSON document, or a key-value pair, but each choice changes what is easy later.

## What you learned

- A database is the durable source of truth for structured application state.
- Schema, indexes, transactions, and constraints protect data meaning and integrity.
- Different database families optimize for different access patterns.
- The database is not the right place for every kind of data or every workload.

## Practice experiments

1. Add a new column on paper and decide whether old rows need a default value.
2. Represent the same short-link mapping as a SQL row, a document, and a key-value
  entry.
3. Explain which query would need an index if the table grew to millions of rows.

## SQL vs document vs key-value

For this URL-shortener, a relational row is natural:

```text
links(code, url, created_at)
```

A document database might store the same mapping as one document:

```json
{
  "code": "abc123",
  "url": "https://example.com",
  "created_at": "2026-07-02T00:00:00Z"
}
```

A key-value store might store:

```text
link:abc123 -> https://example.com
```

All three can work for a simple lookup. The design question is what else the system must do. If you need joins, constraints, and rich queries, relational databases are strong. If you mostly read and write whole nested objects, document databases can be a good fit. If you only need fast lookup by exact key, key-value stores are often simpler.

## Trade-offs

A single database module does not make the data tier infinitely scalable or highly available. It gives you the vocabulary needed to understand later modules:

- Database scaling starts with identifying the pressure: query, connection, read, write, storage, or availability.
- Replication improves read capacity and failover options, but introduces lag.
- Sharding increases write/storage capacity, but makes queries and rebalancing harder.
- Caching reduces repeated reads, but introduces invalidation and staleness.
- Queues smooth bursts, but make work asynchronous.

The first database move is usually not "add every advanced mechanism." It is to understand the data model, measure the bottleneck, add the right index, and only then add more machinery.

## Next steps

- [Database scaling](../database-scaling/README.md) for pressure and growth paths.
- [Replication and failover](../replication-failover/README.md) for availability and stale reads.
- [Object storage](../object-storage/README.md) for large opaque bytes.

## Further reading

- PostgreSQL, "The SQL Language" (used by the runnable lab): https://www.postgresql.org/docs/current/tutorial-sql.html
- PostgreSQL, "Indexes" (used by the runnable lab): https://www.postgresql.org/docs/current/indexes.html
- Martin Kleppmann, *Designing Data-Intensive Applications*, chapters 2-3.

## Cleanup

The demo removes its sample row before exiting. To reset the whole lab:

```bash
make reset
```
