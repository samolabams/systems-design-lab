# Database scaling

**Track:** Components
**Prerequisites:** [Databases](../databases/README.md)

## Outcome

After this module, you should be able to reason about database scaling as a decision tree rather than a list of disconnected techniques. You should be able to explain:

1. Why scaling a database is harder than scaling stateless app replicas.
2. The difference between read pressure, write pressure, storage pressure, connection pressure, and availability risk.
3. Why indexing and query tuning often come before distributed architecture.
4. When vertical scaling, connection pooling, read replicas, failover, sharding, caching, and queues help.
5. What each scaling move costs in consistency, complexity, or operations.
6. Which later module proves each mechanism in the lab.

For the system-wide version of this decision tree, see the scaling map in
[scaling](../scaling/README.md). This module narrows that map to the data tier.

## What you will build or run

1. A decision tree for scaling database reads, writes, storage, and connections.
2. Examples that separate connection pressure from query pressure and data-size pressure.
3. A lab mapping that shows which local components represent common scaling mechanisms.
4. A checklist for choosing between pooling, replicas, partitioning, and sharding.

## Why this matters

A common beginner mistake is to jump straight from "the database is slow" to "we need sharding." That skips the most important systems design question:

```text
Which limit are we actually hitting?
```

A database can be limited by many different things:

- CPU: queries are expensive.
- Memory: useful indexes/data do not fit in cache.
- Disk I/O: reads or writes wait on storage.
- Connections: too many app replicas open too many database sessions.
- Read volume: many callers repeatedly ask for the same data.
- Write volume: one primary cannot accept writes fast enough.
- Storage size: one node cannot hold the dataset comfortably.
- Availability: one node failing takes the system down.

Each limit calls for a different response. This module sets the tone for replication and failover, leader election, and partitioning and sharding: replication, leader election, and sharding are not random add-ons. They are specific answers to specific database scaling and resilience problems.

## Concept

Database scaling is the practice of increasing the useful capacity, reliability,
or operability of the data tier while preserving correctness. It is harder than
scaling stateless services because the database owns durable state. A new app
replica can start empty; a database node must have the right data, constraints,
indexes, and recovery story.

The central habit is to classify the pressure before choosing a mechanism. A
slow query, too many connections, too many repeated reads, a primary failure,
and a dataset that no longer fits on one node are different problems. Treating
all of them as "the database is slow" leads to expensive architecture that may
not solve the real limit.

## How it works

This module is a decision tree over the data tier. The concept is independent of
any one database product. The lab inspects the current base-stack data path, then
connects each kind of pressure to the later module that demonstrates the
mechanism. The base stack already includes a connection pooler, so connection
pooling is visible before adding any distributed data system.

## The decision tree

Use the cheapest correct move before adding distributed complexity.

| If the pressure is... | First investigate... | Later mechanism |
|---|---|---|
| One query is slow | query plan, index, schema/access pattern | better indexes or query rewrite |
| Too many app connections | connection pooling | connection pooler |
| Machine is near CPU/RAM/IO limits | vertical scaling | larger instance, faster disk |
| Reads dominate | read replicas or cache | Replication and failover, caching |
| Primary may fail | standby and failover | replication and failover, leader election |
| Writes/storage exceed one node | partitioning/sharding | Partitioning and sharding |
| Bursts overwhelm writes | queue and process async | async queues |
| You cannot see the bottleneck | metrics, logs, traces | observability |

The table is not a strict order for every system. It is a bias toward evidence. Measure first, then choose the mechanism that matches the pressure.

## Core ideas

### 1. Start with one good database

A single well-modeled, well-indexed database can go far. For many products, the first scaling move is not sharding. It is:

- choose a data model that matches the access pattern
- add the right indexes
- avoid unnecessary joins or scans on hot paths
- keep transactions short
- pool database connections
- measure slow queries

### 2. Scale vertically before distributing writes

Vertical scaling means giving one database node more CPU, RAM, disk throughput, or storage. It is operationally simpler than sharding because the application still sees one database.

Vertical scaling has a ceiling: eventually the machine becomes too expensive, too large, or still not enough. But it is often the lowest-complexity step before changing the architecture.

### 3. Protect the database from connection pressure

Scaling app replicas can accidentally harm the database. Ten app replicas with large connection pools can open hundreds of database connections. Each connection consumes memory and scheduling overhead.

Connection pooling keeps many app requests flowing through a smaller number of database sessions. In this lab, the base path is:

```text
app replicas -> connection pooler -> Postgres primary
```

The transferable concept is the pool between many app processes and fewer
database sessions.

### 4. Scale reads differently from writes

Read-heavy systems often get relief from:

- **Read replicas** - copy data to follower nodes and route some reads there.
- **Caching** - keep hot data in a faster store or at the edge.

Both have correctness costs. A read replica can lag behind the primary. A cache can become stale. Those are not implementation details; they are user-visible design trade-offs.

### 5. Availability is not the same as capacity

A standby replica can improve recovery after failure even if it does not increase write throughput. Failover answers: "what happens when the primary dies?"

Automatic leader election answers: "how does the group choose a new write leader without a human clicking promote?"

### 6. Sharding is for write/storage ceilings

Sharding splits data across nodes. It can increase write capacity and storage capacity, but it adds difficult questions:

- What is the shard key?
- What happens to cross-shard queries?
- How are hot keys handled?
- How does rebalancing work when nodes are added or removed?
- How does the application find the right shard?

That is why sharding should be treated as a deliberate response to a real ceiling, not as the default first move.

## How this lab maps the decision tree

| Concept | Lab proof |
|---|---|
| database fundamentals | [Databases](../databases/README.md) |
| read replicas, lag, manual failover | [Replication and failover](../replication-failover/README.md) |
| automatic leader election and quorum | [Leader election and replica sets](../leader-election-replica-sets/README.md) |
| partitioning, shard movement, rebalancing | [Partitioning and sharding](../partitioning-sharding/README.md) |
| cache read offload and staleness | [Caching](../caching/README.md) |
| queue write smoothing and backpressure | [Async queues](../async-queues/README.md) |
| measuring bottlenecks | [Observability](../observability/README.md) |
| when not to add machinery | [When not to scale](../when-not-to-scale/README.md) |

## Run

This is a reasoning module over the base stack. Start the base system, then use the guided demo:

```bash
pwd
make base
./modules/database-scaling/demo.sh
```

To run without pauses:

```bash
AUTO=1 ./modules/database-scaling/demo.sh
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

Read the demo commands as inspection of the base data path, not as a new scaling
mechanism. The point is to identify which pressure exists before choosing a
module such as replication and failover, partitioning and sharding, caching, or async queues.

## How to read the output

Output showing the connection pooler in the path points to connection management. Output
showing private Postgres networking points to isolation. Output showing one
shared database behind many app replicas explains why app scaling and database
scaling are different problems.

## What to observe

1. **The database is private** - the host reaches the app through the gateway, not Postgres directly.
2. **The app tier can scale faster than the data tier** - app replicas are interchangeable, but they still share one database.
3. **Connection pooling is already in the path** - the pooler sits between app replicas and Postgres.
4. **A slow query is not a reason to shard** - inspect the query path and indexes first.
5. **Different pressures point to different modules** - read scale, failover, election, sharding, caching, and queues solve different problems.

## What you learned

- Database scaling starts by naming the bottleneck precisely.
- Connection pooling, read replicas, indexes, partitions, and shards solve different problems.
- Scaling the app layer can increase pressure on the database layer.
- Every database scaling mechanism changes operational complexity and failure behavior.

## Practice experiments

1. Given "reads are high but writes are fine," choose whether to investigate
	replication and failover, caching, or async queues first, and justify the choice.
2. Given "one query is slow," explain why an index comes before sharding.
3. Given "writes arrive in bursts," explain why async queues may help without increasing
	total write capacity.

## Trade-offs

- **Vertical scaling is simple but finite.** It avoids distributed data complexity, but one node still has a ceiling.
- **Read replicas improve read capacity but can be stale.** Read-after-write paths may need the primary.
- **Failover improves recovery but does not make writes unlimited.** It is an availability tool, not a write-scaling tool.
- **Sharding increases write/storage capacity but changes the application.** Shard keys, hot keys, and cross-shard queries become design concerns.
- **Caching reduces read pressure but introduces invalidation.** The cache is usually not the source of truth.
- **Queues smooth bursts but make work asynchronous.** Users may see accepted-but-not-finished operations.

## Next steps

- [Databases](../databases/README.md) for the basic data-store role.
- [Replication and failover](../replication-failover/README.md) for read replicas and promotion.
- [Partitioning and sharding](../partitioning-sharding/README.md) for splitting data by key.

## Further reading

- PostgreSQL, "Monitoring Database Activity": https://www.postgresql.org/docs/current/monitoring.html
- PostgreSQL, "Using EXPLAIN": https://www.postgresql.org/docs/current/using-explain.html
- PgBouncer documentation: https://www.pgbouncer.org/usage.html

## Cleanup

This module does not create persistent lab data. To reset the whole lab:

```bash
make reset
```
