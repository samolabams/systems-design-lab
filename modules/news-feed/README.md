# Design A News Feed

**Track:** Capstones

## Before you start

Complete or skim these modules first: [The design method](../design-method/README.md),
[Estimation](../estimation/README.md), [Caching](../caching/README.md),
[Event streaming](../event-streaming/README.md), [Database scaling](../database-scaling/README.md),
and [Partitioning and sharding](../partitioning-sharding/README.md). They provide
the vocabulary this capstone expects.

## Outcome

After this capstone, you should be able to design a news feed that
balances fan-out-on-write, fan-out-on-read, ranking, hot users, cache strategy,
storage layout, and eventual consistency. You should be able to explain which
part of the feed is source-of-truth data, which part is derived serving state,
and which path pays the cost of building each user's feed.

## What you will build or run

1. A design artifact for a feed system with posting, fanout, ranking, and reads.
2. A choice between fanout-on-write, fanout-on-read, or a hybrid approach.
3. A data model for users, follows, posts, timelines, and ranking metadata.
4. A trade-off summary for freshness, cost, latency, and celebrity accounts.

## Why this matters

A social feed ("show recent posts from followed accounts") is a standard test of
read/write trade-offs at scale. A naive query becomes expensive under fan-out,
and the appropriate design depends on the follower graph. This capstone requires
a decision between **fan-out-on-write** and **fan-out-on-read** and introduces
the celebrity hot-key problem.

The product appears simple because the user sees one list. The system is not
simple because that list is a materialized view over a changing social graph.
Every design is choosing when to assemble that view: at post time, at read time,
or partly in advance and partly on demand.

## Concept

Apply the [design method](../design-method/README.md):

- **Fan-out-on-write (push)** — when a user posts, write that post into every
  follower's precomputed feed. Reads become a simple lookup; writes are
  expensive and amplify with follower count.
- **Fan-out-on-read (pull)** — store posts once; build each feed by querying the
  accounts a user follows at read time. Writes are inexpensive; reads are
  expensive and repeated.
- **The celebrity / hot-key problem** — a *hot key* is one record hit far more
  than the rest; fan-out-on-write explodes for a user with millions of followers
  (one post → millions of feed writes). The usual fix is a **hybrid**: push for
  normal users and pull for celebrities, avoiding a millions-of-writes spike
  while preserving efficient reads for most users.
- **Caching** — precomputed feeds live in [caching](../caching/README.md) for
  fast reads.
- **Sharding** — the post/feed store is partitioned with
  [Partitioning and sharding](../partitioning-sharding/README.md); hot shards must be considered.

## How it works

This capstone is a workload-shape exercise. The design document should compare
fan-out-on-write, fan-out-on-read, and hybrid feed generation, then justify the
choice with follower distribution, read/write ratio, freshness requirements, and
hot-user behavior.

## Task

Apply the [design method](../design-method/README.md) end-to-end and write
a short design document. There is no required runnable demo. For optional
prototyping, start the referenced module profiles and model fan-out over a post
graph. A strong answer:

1. Shows fan-out-on-write gives fast reads but write cost scales with follower count.
2. Shows fan-out-on-read gives inexpensive writes but expensive, repeated read-time joins.
3. Handles the celebrity poster — pure push is untenable, so a hybrid fixes it.
4. Uses cached precomputed feeds to keep the read path fast under load.

Use this design-document outline:

| Section | What to include |
|---|---|
| Requirements | posting, feed reads, freshness target, ranking needs, privacy, availability and latency targets |
| Estimates | users, follows per user, posts/sec, feed reads/sec, celebrity follower distribution |
| API contract | create post, read feed, follow/unfollow, pagination, freshness/ranking parameters |
| Data model | users, follows, posts, feed entries, ranking metadata, cache keys |
| Fan-out design | push, pull, or hybrid; worker flow; celebrity handling; rebuild strategy |
| Scaling plan | shards, caches, queues/logs, hot users, read replicas, backfills |
| Failure modes | delayed fan-out, duplicate feed entry, stale cache, deleted post, worker backlog |
| Trade-offs | read cost vs write cost, freshness vs latency, ranking quality vs compute cost |

Grade the result with the same dimensions as [method.md](../design-method/method.md):
requirements, estimates, API/data model, component choices, scaling bottlenecks,
consistency, operability, and explicit trade-offs.

## How to read the task

Read this as a workload-shape problem. The deciding inputs are follower graph
distribution, post rate, read rate, freshness target, ranking complexity, and hot
accounts. The design should explain where work is paid: on write, on read, or in
a hybrid path.

## How to read the output

A strong design document separates post storage, fan-out workers, feed storage,
cache, ranking, and read serving. It should explicitly handle celebrity users and
state which feed entries can be stale. If all users follow the same path, the
design probably misses the skew problem.

Read the artifact as evidence about cost placement. A push design should show
large write amplification but cheap reads. A pull design should show cheap writes
but repeated read-time work. A hybrid design should say exactly which accounts
switch paths and how the read service merges pushed and pulled entries.

## What to observe

1. **Fan-out moves cost between writes and reads** - the right answer depends on workload shape.
2. **Celebrity users break uniform assumptions** - hot accounts usually need a hybrid path.
3. **Feed storage is derived state** - it can be rebuilt, but rebuilding has cost and freshness trade-offs.
4. **Ranking changes the data path** - a chronological feed and ranked feed need different computation.

For each major choice, write one sentence in this form:

```text
This feed design pays the cost at _____ because the workload has _____.
```

## What you learned

- Feed systems are shaped by read/write ratio, follow graph shape, and freshness requirements.
- Fanout-on-write and fanout-on-read move cost to different moments.
- Ranking and pagination affect both product behavior and data access patterns.
- Hot accounts and large fanout require special handling.

## Practice experiments

1. Redesign for a celebrity with 50 million followers.
2. Add ranking by engagement and explain where the ranking job runs.
3. Tighten freshness from minutes to seconds and identify which components become
  stressed.

## Trade-offs

- **Read- vs write-optimised** — the choice is fundamentally "pay on write" vs
  "pay on read"; the follower distribution determines which cost is lower.
- **Freshness vs cost** — precomputed feeds can be slightly stale; rebuilding on
  every read is fresh but costly.
- **Hybrid complexity** — two code paths (push + pull) merged at read time is more
  complex but necessary at scale.
- **Hot shards** — popular users/topics concentrate load; needs careful keying.

## Next steps

- [Caching](../caching/README.md) for hot timelines.
- [Event streaming](../event-streaming/README.md) for feed update pipelines.
- [Database scaling](../database-scaling/README.md) for storage and query pressure.

## Further reading

- Alex Xu, *System Design Interview*, ch. "Design a News Feed".
- "Fanout on write vs read" — high-scalability discussions of Twitter/Instagram
  feeds.
- Referenced modules: [caching](../caching/README.md),
  [partitioning and sharding](../partitioning-sharding/README.md).

## Cleanup

Only if profiles were started for prototyping:

```bash
make reset
```
