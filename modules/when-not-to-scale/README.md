# When NOT to scale

**Track:** Foundations
**Prerequisites:** none

> **Status:** Runnable - uses lab measurements to argue against premature scaling machinery.

## Outcome

After this module, you should be able to argue against premature
complexity with evidence: measure the current bottleneck, optimize the simple
path first, and add scaling machinery only when the estimate and observation
justify it.

## What you will build or run

1. A set of scenarios where scaling is not the first or best fix.
2. A checklist that separates product need, measurement, and engineering response.
3. Examples where simpler changes beat new infrastructure.
4. A decision habit for delaying complexity until evidence supports it.

## Why this matters

The rest of the guide covers scaling machinery — replicas, caches, shards,
queues. This module is the deliberate counterweight: **most systems add that
machinery far too early.** Premature sharding, caching everything, and
queue-everything are anti-patterns that buy complexity, new failure modes, and
operational cost without a measured need. A well-tuned single Postgres instance
plus one read replica can serve substantial load (estimation). Require evidence before
adding complexity.

## Concept

Each scaling tool solves a *specific* **bottleneck** — the one resource that runs
out first and caps the whole system — and carries a *specific* cost. Adding it
speculatively means you pay the cost without removing a real ceiling:

- **Sharding (partitioning and sharding)** removes a write/storage ceiling — but adds *rebalancing*
  (moving data when you add/remove a shard), *cross-shard queries* (a query that
  must visit several shards and combine the results), and a routing layer.
- **Caching (caching)** removes read latency on a *hot set* (the small slice of data
  that gets most of the reads) — but becomes a *second source of truth* you must
  **invalidate** (drop or refresh stale entries) correctly.
- **Queues (async queues)** decouple async work — but add a broker, *delivery semantics*
  (the rules for whether a message can be lost or duplicated), and
  end-to-end observability gaps.
- **Microservices** match team/scale boundaries — but add network latency,
  *partial failure* (one service is down while others are up), and
  distributed-ops cost.

## How it works

The base system is already enough to serve meaningful load: one gateway, N
**stateless** app replicas, and one Postgres reached through **PgBouncer**.
"Stateless" means the replicas hold no per-client data, so any one of them can
handle any request; PgBouncer is a connection pooler that lets all those app
processes share a small pool of database connections. This demo sends real
traffic with **no cache, no shard, no queue** and observes whether p95 remains
healthy. The lesson is that the *first* scaling move is usually "add a replica,
tune the query, or use a larger server," not "introduce a distributed subsystem."

Use this decision checklist before adding infrastructure:

| Question | If the answer is no |
|---|---|
| Do we know which resource is saturated? | measure first; do not choose a mechanism yet |
| Is the hot path identified? | trace/profile the path before changing architecture |
| Has the simple fix been tried? | tune query, add index, adjust pool, increase instance size, or add stateless replicas |
| Is the added component removing the measured bottleneck? | reject it as premature complexity |
| Can we operate the new failure modes? | delay until ownership, alerts, backups, and rollback exist |

A good design answer can say "not yet" and name the metric that would change the
decision later.

## Run

```bash
pwd
make base
make scale N=2
make load            # observe p95 with NO cache/shard/queue
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

Read this as a restraint exercise. The commands intentionally avoid Redis,
shards, queues, and extra profiles. The only scaling move is adding stateless app
replicas.

## How to read the output

If p95 stays healthy and error rates stay low, the base architecture is still
sufficient for this load. If latency rises, identify the saturated component
before choosing a mechanism. A slow query calls for indexing before sharding; a
hot repeated read may justify caching; slow background work may justify a queue.

## What to observe

1. The base system comfortably serves the k6 load with healthy p95 — *before*
   any caching/partitioning and sharding machinery exists.
2. Scaling app replicas (`N=2`) is a one-line change with no new subsystem — the
   cheapest scaling move, and often sufficient.
3. The eventual ceiling is the **shared Postgres**, not the app tier — which
   tells you the *next* move to investigate (add a read replica / tune the
   query), rather than jumping straight to "shard everything".

## What you learned

- Scaling without evidence can make a system more expensive and harder to operate.
- Measurement should identify the bottleneck before a mechanism is chosen.
- Sometimes the right fix is simpler code, better queries, caching, or product limits.
- Not scaling yet can be a deliberate engineering decision.

## Practice experiments

1. Write down the exact metric that would justify adding caching.
2. Write down the exact metric that would justify adding async queues.
3. Decide which single optimization you would try before Partitioning and sharding.

## Trade-offs

- What is the single Postgres instance limited by here: CPU, connections, or IO
  (input/output — reads and writes to disk)? Measure before assuming.
- Which is cheaper: one bigger DB (*vertical* scaling — a more powerful machine)
  or the permanent operational cost of a shard? For most workloads the larger
  server remains sufficient for a long time, but this depends on growth rate and write
  volume, so re-check it with a number (estimation) rather than treating it as a rule.
- Complexity is a debt with interest; add it only when a measured bottleneck
  (estimation/availability) names the *specific* component that removes it.

## Next steps

- [Estimation](../estimation/README.md) for sizing the problem.
- [Component selection](../component-selection/README.md) for choosing a justified mechanism.
- [Scaling](../scaling/README.md) for when the evidence does support scaling.

## Further reading

- "Use One Big Server" / scale-up arguments (e.g. https://specbranch.com/posts/one-big-server/)
- "The Premature Optimization is the Root of All Evil" — Knuth, on resisting
  speculative complexity (TAOCP / widely quoted).
- *Designing Data-Intensive Applications*, Ch. 1 — "scaling up vs scaling out".

## Cleanup

```bash
make scale N=1
make reset
```
