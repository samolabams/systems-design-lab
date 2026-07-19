# Replication & Failover

**Track:** Components
**Prerequisites:** [Databases](/modules/databases/), [Database scaling](/modules/database-scaling/)

## Outcome

After this module, you should understand replication as a general data-tier
mechanism, not as a universal solution for every database pressure point. You should be able to
explain:

1. Why replicated data can help with read scale and recovery.
2. Why one primary still limits write throughput.
3. What replication lag is and how it causes read-after-write bugs.
4. How manual failover differs from automatic leader election.
5. Why Postgres is the lab implementation, not the replication concept itself.

## What you will build or run

1. A primary/replica database setup with visible replication behavior.
2. A write followed by reads that can reveal replica lag.
3. A failover scenario that shows what changes when the primary is unavailable.
4. A connection between replication, availability, and consistency trade-offs.

## Why this matters

[Scaling](/modules/scaling/) showed why stateless app replicas are relatively
easy to add: each replica can start empty and serve the same code. A database is
different. As [Databases](/modules/databases/) explains, it owns durable state,
and [Database scaling](/modules/database-scaling/) asks you to identify the
pressure before choosing a mechanism.

Replication is useful for two common pressures. First, read traffic can overload
the primary, so some reads may be served by a copy. Second, the primary can fail,
so a standby copy gives the system something to promote. Replication does **not**
make writes unlimited, because there is still one write leader. It also
introduces **replication lag**: a write can commit on the primary before the
replica has replayed it. [Consistency models](/modules/consistency-models/)
names the user-visible trade-off.

The key habit is to separate three questions that often get blurred together:
where do writes go, where may reads go, and which node can become the next
writer? Replication improves the second and third questions, but it usually does
not change the first: one primary still serializes writes.

## Concept

Replication means keeping a copy of data on another node. A replicated data tier
usually has one node that accepts writes and one or more nodes that copy the
write history. In design terms, this gives you two separate capabilities:

- **Read scaling** — route reads to a replica (the app's read/write split),
  taking read load off the primary.
- **Failover** — move the write role to a standby when the primary dies.
  In this lab that is a *manual* operation; contrast [leader election](/modules/leader-election-replica-sets/), where the lab shows
  automatic leader election via consensus.

The cost is **replication lag**: a replica is often eventually consistent,
so a read immediately after a write can miss it — the read-after-write hazard.

The concept is independent of any one database. The lab uses Postgres streaming
replication because the base system already uses Postgres, and because the WAL
stream makes primary/standby replication visible in a small local environment.

## How it works

In the Postgres implementation, the standby first takes a full copy of the
primary's data files with `pg_basebackup`. After that, it follows the primary's
WAL (Write-Ahead Log), the ordered record of changes Postgres must persist before
it considers writes durable.

A *replication slot* acts like a bookmark. It tells the primary which WAL records
the replica still needs, so a replica that briefly disconnects can catch up
without missing changes. Application writes still go to the primary through the
connection pooler. When `DATABASE_REPLICA_URL` is set, the app
can send reads to the replica instead. Until the standby is promoted, it remains
read-only in Postgres recovery mode.

## Run

```bash
make replication-failover
# point the app's reads at the replica:
DATABASE_REPLICA_URL=postgres://app:app@postgres-replica:5432/app make base
./modules/replication-failover/demo.sh
```


## How to read the commands

Read primary-side SQL as writes to the source of truth. Read replica-side SQL as
evidence that WAL changes have been transmitted to and replayed on the replica. Read `pg_promote()` as
a role change: the standby stops following the old primary and becomes writable.

The `DATABASE_REPLICA_URL` command changes the app's read path so redirects can
come from the replica. That is what makes read-after-write lag visible.

## How to read the output

If a row inserted on the primary appears on the replica, the copy is working. If
a redirect temporarily returns `404` after a successful shorten request, the read
hit a replica that has not caught up yet. If `EXPLAIN` changes from sequential
scan to index scan, the database found a cheaper access path; that observation is
included to remind you that indexing often comes before distributed architecture.

Read the output as three different proofs. Row visibility proves copying. Lag
proves the copy is not instantaneous. Promotion proves a role change. Keeping
those separate prevents a common mistake: assuming a replica is simultaneously a
fresh read target, a write scaler, a failover target, and a backup.

## What to observe

1. **Replication works** — INSERT on the primary, then SELECT on the replica
   returns the row.
2. **Lag under load** — drive k6 writes and watch `pg_stat_replication` /
   `pg_last_wal_replay_lsn` lag grow.
3. **Read-after-write 404** — shorten a URL, immediately read it via the replica;
  if lag > 0 the redirect can 404 until the WAL catches up. *This is eventual
  consistency made visible in the lab.*
4. **Indexing** — run a slow `SELECT` with no index, read its `EXPLAIN (ANALYZE)`
    (seq scan), add a B-tree index, and observe it change to an index scan. The
   single highest-leverage DB fix.
5. **Failover drill** — kill the primary, `pg_promote()` the replica, repoint the
   app.

For each database step, write one sentence in this form:

```text
This step proves _____ because the primary/replica state is _____.
```

## What you learned

- Replication copies data to another node for read scaling, durability, or failover.
- Replica lag creates stale-read risk after writes.
- Failover changes which node accepts writes and can interrupt service briefly.
- Read routing must match the consistency needs of each request.

## Practice experiments

1. Route read-your-writes traffic to the primary and explain why the bug
    disappears.
2. Add load before reading the replica and predict whether lag increases.
3. Explain why promotion improves availability but does not increase write
  throughput.

## Trade-offs

- **Async replication** (the default here) keeps write latency low, but it gives
  a non-zero **RPO** (Recovery Point Objective: how much recent data a failure
  can lose). The newest transactions may not have reached the standby when the
  primary dies. **Synchronous replication** can reduce RPO toward zero, but every
  commit must wait for another node to confirm the write.
- Reading from a replica scales reads but exposes lag; route latency-sensitive
  read-your-writes paths back to the primary.
- Replication is **not a backup**. A bad `DELETE` replicates too. Backups,
  restore drills, RPO, and RTO are covered in [multi-region DR](/modules/multi-region-dr/).

## Next steps

- [Consistency models](/modules/consistency-models/) for stale-read reasoning.
- [Leader election and replica sets](/modules/leader-election-replica-sets/) for primary selection.
- [Database scaling](/modules/database-scaling/) for read replicas and connection pressure.

## Further reading

- PostgreSQL, "High Availability, Load Balancing, and Replication":
  https://www.postgresql.org/docs/current/high-availability.html
- PostgreSQL, "Log-Shipping Standby Servers" (streaming replication):
  https://www.postgresql.org/docs/current/warm-standby.html
- Use The Index, Luke — practical B-tree indexing: https://use-the-index-luke.com/

## Cleanup

```bash
make reset
```
