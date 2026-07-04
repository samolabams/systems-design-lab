# modules/ — the guide

Each folder is one self-contained lesson. Folder names are semantic slugs that
match Make targets, so you can run the same name they see in the
guide. For lessons that add infrastructure, the folder name also matches
the Compose profile; lessons that reuse the base stack keep the same target
without adding a profile.

> **Status:** *Runnable* = the lesson has working commands and, where useful, a
> guided demo; *Design exercise* = a capstone exercise worked on paper with
> optional prototyping. **Study role:** *Core* = main sequence; *Specialized* =
> useful in common designs but narrower; *Advanced* = best after the core
> mechanisms are understood.

## New to system design? Start here

**System design** is the process of defining the architecture, components, and
data of a system to meet a set of requirements. In practice, this means choosing and
arranging the parts (servers, databases, caches, queues, networks) so the system
stays fast enough, reliable enough, and affordable as load grows. There is rarely
a single universally correct answer; system design requires deliberate
**trade-off analysis** and justification. This lab develops those trade-offs
through reproducible demonstrations, not only through prose descriptions.

**Read in this order; no prior systems-design knowledge is assumed:**

1. **Foundations first.** The vocabulary and reasoning. Begin with
   [Trade-offs & vocabulary](tradeoffs/README.md) — it defines the words every
   later lesson uses (latency, throughput, stateless, ...).
2. **Then components in the grouped order below.** Start real infrastructure and
   observe each foundation concept in a running system: replica lag, queue
   buffering, object storage, vector retrieval, DNS resolution, and network
   boundaries.
3. **Use [The design method](design-method/README.md) as the lens** that ties
   it all together into a repeatable way to design a system from scratch.

Every lesson is self-contained and follows the same concept-first order.
Runnable lessons include a concrete preview of what will be started, changed,
and observed before the commands begin. Capstones replace the runbook with a
design task. The goal is conceptual understanding: study the explanation, run or
design the scenario, observe or justify the behavior, and relate the result back
to the design trade-off. Unfamiliar abbreviations are defined in the
[Glossary](#glossary-recurring-terms).

## Standard lesson structure

Every module README should follow the same structure so concepts are explained
consistently and in enough depth to understand *before* you run anything:

| Section | Purpose |
|---|---|
| **Outcome** | what you should be able to explain afterward |
| **What you will build or run** | the concrete services, requests, files, or design artifact the lesson will produce |
| **Why this matters** | the real-world problem that motivates the concept |
| **Concept** | enough explanation to understand it without running the demo |
| **How it works** | the mechanism, step by step (how the lab realizes it) |
| **Run / Task** | hands-on commands for runnable lessons, or the design exercise for capstones |
| **How to read the commands / task** | how to interpret command shape and parameters, or how to approach a capstone exercise |
| **How to read the output** | how to connect demo output or a design artifact back to the concept |
| **What to observe** | guided observations or design checkpoints |
| **What you learned** | a short recap of the ideas the output should now make clear |
| **Practice experiments** | small changes or follow-up design variants that reinforce the mechanism |
| **Trade-offs** | when to use / when not, with links to related modules |
| **Next steps** | the most natural follow-up modules or experiments |
| **Further reading** | canonical external sources (official docs, papers, books) |
| **Cleanup** | return to a clean slate |

The preview matters because it gives each lesson a visible target before any
commands run. A good preview names the artifact or behavior, not just the tool:
for example, "a private bucket, an object key listing, a failed unsigned read,
and a working presigned URL" is more useful than "MinIO commands."

## The three tracks

| Track | Covers | Runs on |
|---|---|---|
| **Foundations** | *How to reason and decide* — concepts, math, method | `base` |
| **Components** | *How a mechanism works* — real infrastructure you stand up or inspect | `base`, sometimes with a profile |
| **Capstones** | *Design a whole system yourself* — self-directed exercises against the design-method rubric | paper (optional prototype) |

**Foundations provide the reasoning framework; components provide the executable
mechanism.** Foundations define a trade-off in the abstract; components
demonstrate it in a running system. For example,
[Consistency models](consistency-models/README.md) explains the
read-after-write hazard, and
[Replication & failover](replication-failover/README.md) reproduces that
failure mode through a replica-lag demonstration.

## The core challenges (problem → mechanism map)

Almost all scaling work answers one of a handful of recurring problems. This is
the "which lesson solves my problem" lookup — **foundations name the problem,
components build the fix**:

| Challenge | Symptom | Mechanism | Where |
|---|---|---|---|
| Too many concurrent users | one server reaches its RPS ceiling | replicate logic (load balancing) + read replicas | [Load balancing](load-balancing/README.md), [scaling](scaling/README.md), [replication](replication-failover/README.md) |
| Too much data for one machine | data exceeds one node's storage or throughput capacity | partition by key (sharding) | [Partitioning & sharding](partitioning-sharding/README.md) |
| Writes too slow to be synchronous | request blocks on slow work | make it async with a queue | [Asynchronous processing and queues](async-queues/README.md) |
| Reads hammer the database | repeated reads overload the DB | cache hot data; push to the edge | [Caching](caching/README.md), [edge caching/CDN](edge-caching/README.md) |
| Replicas & async => stale reads | users see outdated/deleted data | pick a consistency model deliberately | [Consistency models](consistency-models/README.md), [replication](replication-failover/README.md) |

The first four come straight from the classic "core challenges of a web-scale
app"; the fifth is the tax you pay for solving the others. Reach for a mechanism
only when an estimate says the problem is real — adding one without a number is
the "when not to scale" anti-pattern.

## Foundations (reasoning layer, run on `base`)

| Lesson | Study role | Status |
|---|---|---|
| [Trade-offs & vocabulary](tradeoffs/README.md) | Core | Runnable |
| [The design method + rubric](design-method/README.md) | Core | Runnable |
| [Back-of-the-envelope estimation](estimation/README.md) | Core | Runnable |
| [CAP / PACELC & consistency models](consistency-models/README.md) | Core | Runnable |
| [Availability & reliability math](availability/README.md) | Core | Runnable |
| [When not to scale](when-not-to-scale/README.md) | Core | Runnable |
| [Multi-region, DR & backups](multi-region-dr/README.md) | Advanced | Runnable |
| [Choosing the right building block](component-selection/README.md) | Core | Runnable |

## Components

Most component lessons add a Compose profile. A few lessons reuse `base` when the
mechanism is already present in the always-on stack.

| Lesson | Study role | Status |
|---|---|---|
| **Core web system path** |  |  |
| [DNS & name resolution](dns/README.md) | Core | Runnable |
| [Load balancing](load-balancing/README.md) | Core | Runnable |
| [API Gateway / Edge Gateway](api-gateway/README.md) | Core | Runnable |
| [Scaling: vertical vs horizontal](scaling/README.md) | Core | Runnable |
| [Service discovery](service-discovery/README.md) | Core | Runnable |
| **Data layer** |  |  |
| [Databases](databases/README.md) | Core | Runnable |
| [Database scaling](database-scaling/README.md) | Core | Runnable |
| [Replication & failover](replication-failover/README.md) | Core | Runnable |
| [Leader election & replica sets](leader-election-replica-sets/README.md) | Core | Runnable |
| [Partitioning & sharding](partitioning-sharding/README.md) | Core | Runnable |
| **Async and distributed workflows** |  |  |
| [Asynchronous processing and queues](async-queues/README.md) | Core | Runnable |
| [Event streaming and replayable logs](event-streaming/README.md) | Core | Runnable |
| [Message delivery semantics, outbox & idempotency](message-delivery-semantics/README.md) | Advanced | Runnable |
| [Distributed transactions & sagas](sagas/README.md) | Advanced | Runnable |
| **Performance and delivery** |  |  |
| [Caching strategies and invalidation](caching/README.md) | Core | Runnable |
| [Edge caching and CDN model](edge-caching/README.md) | Specialized | Runnable |
| [Object storage](object-storage/README.md) | Specialized | Runnable |
| **Interfaces and protection** |  |  |
| [API design: REST vs gRPC vs GraphQL](api-design/README.md) | Core | Runnable |
| [Rate limiting and backpressure](rate-limiting/README.md) | Core | Runnable |
| [Circuit breakers, timeouts and retries](circuit-breakers/README.md) | Core | Runnable |
| **Operations** |  |  |
| [Observability](observability/README.md) | Core | Runnable |
| **Specialized retrieval** |  |  |
| [Vector stores and similarity retrieval](vector-store/README.md) | Specialized | Runnable |

## Capstones (assemble with the [design method](design-method/README.md) self-assessment rubric)

These are **self-directed design exercises**. They do not require a predefined
service profile. Apply the design method, produce a design document, and optionally
start the referenced module profiles to prototype part of the design.

| Lesson | Status |
|---|---|
| [Design TinyURL](tinyurl/README.md) | Design exercise |
| [Design a news feed](news-feed/README.md) | Design exercise |
| [Design a chat system](chat/README.md) | Design exercise |
| [Design a distributed rate limiter](distributed-rate-limiter/README.md) | Design exercise |

## Glossary (recurring terms)

Each term is also defined where it first appears, but these come up everywhere:

| Term | Plain meaning |
|---|---|
| **QPS / RPS** | Queries / Requests Per Second — how much traffic the system handles. |
| **TPS** | Transactions Per Second — like QPS, but counting database transactions (writes). |
| **Latency** | How long *one* request takes (e.g. 20 ms). |
| **Throughput** | How many requests finish per second — the system's capacity. |
| **p95 / p99** | 95th / 99th *percentile* latency: 95% (or 99%) of requests complete faster than this value. These percentiles expose slow-tail behavior that averages can hide. |
| **RTT** | Round-Trip Time — how long a packet takes to reach another machine and come back. |
| **VU** | Virtual User — one simulated concurrent client in the k6 load tool (`make load`). |
| **Stateless** | A service that keeps no per-client data in memory, so any copy can serve any request; see [Trade-offs & vocabulary](tradeoffs/README.md) and [Scaling](scaling/README.md). |
| **Idempotent** | An operation that is safe to repeat: doing it twice has the same effect as doing it once; this matters when a queue redelivers a message. |
| **WAL** | Write-Ahead Log — a database records each change in an append-only log *before* applying it; Postgres ships this log to its replicas. |
| **Replica / standby** | A read-only copy of a database that follows the primary; see [Replication & failover](replication-failover/README.md). |
| **Gateway / reverse proxy** | The front door that receives every request and forwards it to a backend; see [Load balancing](load-balancing/README.md). |
| **SLI / SLO / SLA** | Measured signal / internal target / contractual promise for reliability; see [Availability & reliability math](availability/README.md). |
| **RPO / RTO** | How much data you may lose / how long recovery may take, in a disaster; see [Multi-region, DR & backups](multi-region-dr/README.md). |
| **AMQP** | The messaging protocol RabbitMQ speaks; see [Asynchronous processing and queues](async-queues/README.md). |
| **Eventual consistency** | Copies of the data may lag but agree *eventually* once updates propagate; a read just after a write can miss it. |
| **Partition (network)** | A break that stops some nodes from reaching others, splitting a cluster into groups that cannot synchronize. |
| **Quorum** | A majority of nodes (more than half); a decision needs a quorum to be safe under failure. |
| **Consensus** | How nodes agree on one value (e.g. who is leader) despite crashes; Raft and Paxos are the classic algorithms. |
| **Shard** | One horizontal slice of a dataset split across machines by key, so no single node holds it all; see [Partitioning & sharding](partitioning-sharding/README.md). |
| **Hot key / hot set** | The small slice of data that receives most of the traffic — the part worth caching, pushing to the edge, or protecting. |
| **TTL** | Time To Live — a countdown after which a cache entry, lease, or registration expires. |
| **Embedding / vector store** | An embedding is a numeric representation of meaning or features; a vector store/index finds nearby embeddings for semantic retrieval, recommendations, image similarity, or similar-item search. |

## Why folders match commands

Folder names match Make targets so lesson commands stay predictable. For
example, `modules/async-queues/` maps to `make async-queues`, and because that
lesson adds RabbitMQ and workers, it also maps to the `async-queues` Compose
profile. Lessons such as `api-gateway`, `load-balancing`, and `databases` reuse
the base stack, so their Make targets start `base` without adding an extra
profile.
