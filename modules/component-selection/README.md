# Component selection (choosing the right building block)

**Track:** Foundations
**Prerequisites:** [The design method](../design-method/README.md)

## Outcome

After this module, you should be able to choose a building block
from workload requirements: data shape, read/write ratio, consistency needs,
query pattern, latency budget, durability, fan-out, and operational cost.

## What you will build or run

1. A requirements-first comparison table for common infrastructure building blocks.
2. A symptom-to-mechanism decision path for choosing the right component.
3. Worked examples where adding a component helps and where it adds avoidable complexity.
4. A component-choice checklist you can reuse in capstone design documents.

## Why this matters

The component modules show how each building block behaves through a focused
demonstration. In a real design, or in [design method](../design-method/README.md) step 4, the skill is
**choosing between alternatives**: SQL or NoSQL? RabbitMQ or Kafka? Redis or
Memcached? cache-aside or write-through? Choosing the wrong default is one of the
most common ways a design goes wrong, and reaching for a heavyweight tool ("let's
use Kafka") without a reason is the when not to scale anti-pattern in disguise. This module is
the decision layer that sits on top of the mechanisms.

## Concept

A component category solves a *problem*; the products inside it trade off along a
few axes. Learn the **category and its axes**, and the specific product almost
follows from the requirements (the adjectives extracted in
[design method](../design-method/README.md) step 1).

The rule: **name the category from the problem, then pick the product from the
constraint** — never the reverse.

For data-layer decisions, connect this catalog to the decision tree in
[database scaling](../database-scaling/README.md). Measured read pressure points
toward replicas or caching, write and storage ceilings point toward partitioning
or sharding, burst pressure points toward queues, and blob delivery points toward
object storage plus edge caching.

## How it works

Each table below is "for this category, when do I reach for which?" The right
column is the deciding constraint, not a feature list.

### Data store

| Option | Reach for it when | Trade-off | Demo |
|---|---|---|---|
| Relational (Postgres/MySQL) | ACID, joins, strong consistency are required | vertical-scale ceiling; sharding is manual | [Databases](../databases/README.md) |
| Document (MongoDB) | schema varies per record, nested data, few joins | weak cross-document transactions | [Databases](../databases/README.md) |
| Key-value (Redis/DynamoDB) | point lookups by key at large scale | no rich queries | [caching](../caching/README.md) |
| Column-family (Cassandra) | write-heavy, time-series, multi-DC | eventual consistency; query-first modeling | [event streaming](../event-streaming/README.md) |
| Object store (S3) | large blobs: images, video, backups | not for low-latency mutable rows | [object storage](../object-storage/README.md) |
| Vector store / vector index | semantic retrieval, recommendations, similar-item search, image similarity | approximate results; embedding generation and refresh cost | [vector store](../vector-store/README.md) |

A few terms in that table: **ACID** is the relational promise that a transaction
either fully happens or not at all, and once committed it sticks. A relational DB
hits a *vertical-scale ceiling* — it grows by using a larger machine, and
sooner or later there is no bigger machine — and splitting its data across several
machines is *manual*, something the system designer must design and operate (partitioning and sharding). A
*cross-document transaction* is one all-or-nothing change touching several
records at once, which document stores handle weakly. *Rich queries* means
flexible SQL-style filtering, joining, and aggregating rather than only fetching
by key. *Query-first modeling* means you shape the data around the reads you
intend to run instead of around a tidy model. And **S3** is Amazon's Simple
Storage Service, the object store everything else imitates. A vector store is for
similarity over embeddings: semantic retrieval, recommendations, and retrieval
for semantic systems.

**Default:** start relational. Move off it only when a real number — dataset
size, write rate, or how often the record shape changes — forces the decision.

### Messaging

| Option | Reach for it when | Trade-off | Demo |
|---|---|---|---|
| Queue (RabbitMQ/SQS) | decouple work, competing consumers, ack-per-message | deletes on consume; no replay | [async queues](../async-queues/README.md) |
| Log (Kafka) | high throughput, replay, event sourcing, multiple readers | offsets and retention must be operated | [event streaming](../event-streaming/README.md) |
| Managed (SQS) | managed operations are required | fewer routing features | [async queues](../async-queues/README.md) |

The distinction turns on what happens to a message after it is read. A queue
*deletes on consume* — once a worker takes a message, it is gone, with no way to
read it again. A log keeps everything, so consumers can *replay* history from the
beginning, each tracking its own *offset* (its bookmark position in the log). The
price is that the system must manage retention and offsets, which increases
operational work. A *managed* option like SQS moves that operational burden to
the cloud provider. It still requires configuration, but the broker itself is no
longer operated by the application team.

**Deciding axis:** do consumers need to *replay* history? Yes → log. No → queue.

### Cache

| Option | Reach for it when | Trade-off | Demo |
|---|---|---|---|
| Redis | rich types (sorted sets, counters), persistence option | single-threaded; more memory overhead | [caching](../caching/README.md) |
| Memcached | simple key→blob caching | no data structures, no persistence | [caching](../caching/README.md) |
| CDN (Cloudflare/CloudFront) | static assets served near the user | only for cacheable, mostly-static content | [edge caching](../edge-caching/README.md) |

Redis is *single-threaded*: it runs one command at a time on a single CPU core,
which keeps its behaviour simple and predictable but means one slow command holds
up the rest. In return it provides real *data structures* — lists, sets, sorted
sets, counters — not just plain values, and an optional *persistence* mode that
writes to disk so data survives a restart. Memcached does not provide those
features; it caches a key to a blob. A CDN caches *static content* —
files like images, CSS, and JS that rarely change, so it is safe to serve them
from far away, near the user.

**Write strategy** (independent of which product is selected): *cache-aside* — the
app reads the cache, and on a miss loads from the DB and fills the cache itself
(the common default); *write-through* — every write goes to cache and DB together
(consistent, but slower writes); *write-behind* — write to cache now and flush to
the DB later (fast writes, but the not-yet-flushed data can be lost on a crash).

### Request entry points

| Option | Reach for it when | Trade-off | Demo |
|---|---|---|---|
| L4 load balancer (HAProxy) | raw TCP throughput, simple routing | no awareness of HTTP semantics | [load balancing](../load-balancing/README.md) |
| L7 reverse proxy (Nginx) | path/header routing, TLS, caching | slightly more overhead per request | [load balancing](../load-balancing/README.md) |
| API gateway (Kong/Nginx+) | auth, rate-limit, aggregation across services | one more hop and component to scale | [API design](../api-design/README.md) |

The **L4** and **L7** labels come from where in the network stack each one
operates. An L4 (Layer 4, transport) balancer forwards raw TCP connections
without looking inside them — very fast, but blind to URLs and headers. An L7
(Layer 7, application) proxy reads the HTTP request itself, so it can route by
path or header, terminate TLS, and cache. Each extra component a request passes through
is one more *hop*, and every hop adds a little latency.

## Run

Nothing to start. Apply the catalog to an [design method](../design-method/README.md)
problem statement, list the categories required by the use cases, and justify each product
choice from a requirement. If the deciding constraint cannot be named, the
component is not yet justified (when not to scale).

### Worked example: choosing components from requirements

Problem statement: users upload profile photos, then other users view those
photos frequently. The application also stores the profile owner's user ID,
display name, and moderation status.

| Requirement | Category | Product choice | Why |
|---|---|---|---|
| Store large image bytes durably | object store | S3-compatible object storage, MinIO in this lab | blobs do not need joins or row-level transactions |
| Store owner, object key, status, and timestamps | relational database | Postgres in this lab | metadata needs constraints, transactions, and indexed lookup |
| Serve repeated public reads quickly | CDN / edge cache | edge caching module | hot images should not hit the origin every time |
| Generate a temporary private download link | application + object store | presigned URL | app authorizes the user, storage serves the bytes |

Notice the order: first name the problem category, then choose the product. If
someone says "use Kafka" for this example, ask which requirement needs replayable
event history. If none does, Kafka is not justified yet.

## How to read the commands

There are no infrastructure commands in this module. Read the catalog as a set
of decision tables. Each row names a component category, what it is good at, and
the operational cost it introduces.

## How to read the output

The output is a component-selection rationale. A strong answer names the category
first, then the product. For example, choose "replayable event log" before naming
Kafka, or "object store" before naming S3 or MinIO.

## What to observe

1. Every good choice traces back to an **adjective/number from the requirements**,
   not to familiarity with the product.
2. The **category** is usually obvious from the problem; the **product** comes
   down to one or two axes (replay? joins? blob size?).
3. When two options look equally fine, the tie-breaker is **operational cost** —
  pick the one the team can operate.

## What you learned

- Components should answer a specific requirement or failure mode.
- The same symptom can have multiple possible mechanisms, each with trade-offs.
- Adding infrastructure without a measured need can make a system harder to operate.
- Good design explanations connect requirements, estimates, and consequences.

## Practice experiments

1. Pick news feed capstone and choose storage, cache, queue/log, and gateway components.
2. Replace one chosen product with another in the same category and state what
   changes operationally.
3. Decide whether a recommendation feature needs a relational query, cache, or
  vector store.
4. Identify one component that would be overkill for the stated requirements.

## Trade-offs

- This catalog is a *starting default*, not a rule. The component demonstrations
  provide the evidence needed to choose a different component when justified.
- Picking a powerful component (Kafka, Cassandra) "to be safe" is a real cost:
  ops burden, more failure modes, harder hiring. Match the tool to the load.
- Managed services trade money and lock-in for fewer operations — often the right call
  early, worth revisiting at scale.

## Next steps

- [When not to scale](../when-not-to-scale/README.md) for avoiding premature complexity.
- [Estimation](../estimation/README.md) for sizing the actual problem.
- [The design method](../design-method/README.md) for turning choices into a complete design.

## Further reading

- Martin Kleppmann, *Designing Data-Intensive Applications* — Ch. 3 (storage
  engines) & Part II (distributed data). https://dataintensive.net/
- AWS, "Databases on AWS — purpose-built" (category framing):
  https://aws.amazon.com/products/databases/
- Kafka vs RabbitMQ (official positioning): https://www.rabbitmq.com/blog/2021/07/13/rabbitmq-streams-overview
- "System Design Primer" — Main Components overview:
  https://github.com/donnemartin/system-design-primer#index-of-system-design-topics

## Cleanup

Nothing to tear down.
