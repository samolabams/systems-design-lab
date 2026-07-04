# infra/database — durable state (Postgres + PgBouncer)

Where the system keeps data that must survive restarts. Compute is easy to scale
(add stateless app replicas); **state is the hard part** — there is one source
of truth.

## What's here

- `postgres/init/` — SQL run once on first boot (**auth + replication setup
  only** — generic, no application schema here).
- `postgres/primary/` — the primary's `postgresql.conf` + `pg_hba.conf`
  (WAL/replication tuned, md5 auth so PgBouncer can connect).
- `postgres/replica/setup-replica.sh` — bootstraps a streaming standby with
  `pg_basebackup` (enabled by `make replication-failover`).
- `postgres/pgbouncer/` — a connection **pooler** in front of Postgres. Apps open
  many short connections; PgBouncer multiplexes them onto a few real ones.

> **Separation of concerns:** this folder stays application-agnostic. Each
> example app owns its own schema and applies it on boot — see
> [apps/url-shortener](../../apps/url-shortener), which runs Knex migrations (`migrations/`)
> against the primary to create the `links` table.

## The lesson

Reads scale by routing `SELECT`s to a replica; the cost is **replication lag**
(eventual consistency → read-after-write hazards). Failover is manual here.

**Used in:** replication and failover (replication & failover); network isolation / DMZ is enforced by the base network split.
