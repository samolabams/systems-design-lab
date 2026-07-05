# Systems Design Lab — Build Spec

A single-repo, Docker Compose–based **practice lab** for systems design. Anyone
can use it to go beyond theory and watch real systems behave in realtime: spin
up only the services a lesson needs, reproduce the scenario (load, failure,
partition, lag), and observe what actually happens — not what a diagram claims.

The mission: pair every concept with a **runnable demo** so readers build
intuition by *doing*. Read the idea, run it, break it, watch it recover, then
reuse the same base as a starting point for designing systems of their own.

- **Repo root:** `/Users/samolabamiji/Documents/workspace/systems-design`
- **Audience:** self-study readers using the lab independently.
- **Status of this document:** historical build spec / blueprint. It explains
  the design intent and how the pieces fit together; the current implementation
  status lives in [README.md](README.md) and [modules/README.md](modules/README.md).

---

## 1. Design principles

1. **One repo, profile-gated services.** A shared "base system" is always on.
  Each module has a Make target. Lessons that need extra infrastructure
  activate only those services via Docker Compose
  [profiles](https://docs.docker.com/compose/profiles/). No lesson should
  require booting the entire stack.
2. **Every concept is reproducible.** Each module ships a guided `demo.sh` script
  that drives the scenario step by step (apply load, kill a
   node, induce lag, partition the network) so the behavior is observable, not
   just described.
3. **Observable by default.** Health endpoints expose which instance served a
   request; metrics and logs make internal state visible.
4. **Reusable base.** The base system (gateway → app → connection pool → DB) is
  a realistic skeleton readers can fork to build their own sample systems.
5. **Safe to break.** `make reset` returns to a clean slate. Chaos is a
   first-class, intentional action (`make chaos`).

---

## 2. Tech stack

| Concern | Technology |
|---|---|
| Runtime / app | Node.js + Express (reference impl; runtime-swappable — see §4) |
| Relational DB | Postgres (primary + streaming replica) |
| Connection pooling | PgBouncer |
| Replica-set election lab | MongoDB (3-node replica set) |
| Message queue | RabbitMQ |
| Event log / streaming | Kafka (KRaft mode, no Zookeeper) + kafka-ui |
| Cache | Redis |
| Gateway / LB / reverse proxy | Nginx (HAProxy as an load balancing contrast variant) |
| Object / blob store | MinIO (S3-compatible) |
| Vector store | Qdrant (local specialized vector database) |
| Service discovery | Consul (or etcd) |
| RPC / contracts | gRPC + Protobuf (REST and GraphQL for contrast) |
| Observability — metrics | Prometheus + Grafana + cAdvisor + postgres-exporter |
| Observability — traces / logs | OpenTelemetry + Tempo (traces) + Loki (logs) |
| Load generation | k6 |

The object store, vector store, service discovery, and API-contract demos are **optional,
profile-gated**. The base runtime never requires them, keeping
the always-on footprint small.

---

## 3. Networking model

Two Docker networks enforce a DMZ pattern used throughout the guide:

- `frontend` — published/edge network (gateway lives here).
- `backend` — `internal: true`. Databases and internal services attach here and
  are **unreachable from the host**.

---

## 4. Base system (always on, no profile)

```
nginx gateway ──> app (Node/Express, read/write DB split) ──> pgbouncer ──> postgres-primary
```

- The `app` performs a **read/write split**: writes go to the primary, reads can
  be routed to a replica (when the replica profile is active).
- The `nginx gateway` is the system's **API gateway**: a single entry point that
  owns cross-cutting concerns — routing/load balancing (load balancing),
  rate limiting (rate limiting). Modules progressively load these
  responsibilities onto it instead of into the app.
- `apps/url-shortener` endpoints (entrypoint `server.js`; handlers in `src/routes/`):
  - `POST /shorten` and `GET /:code` — a URL-shortener API (the sample domain).
  - `GET /health` — returns the container hostname, so you can *visually prove*
    which replica/instance served a request.
  - `POST /jobs` — enqueues work to RabbitMQ when the queue profile is active.

### The app contract (runtime-swappable)

The app is the *least* interesting box in the diagram — a thin shell over a
database and a queue. The systems-design material is in the infrastructure (LB,
replication, queues, caching), which is language-agnostic. So the app is defined
by a **contract**, not a language: anything that satisfies it can drop in.

Node/Express is the **reference implementation** kept canonical so every
`demo.sh` behaves identically. But because each service builds from its own
`Dockerfile`, polyglot already works for free — point the build context at your
own folder (e.g. `apps/url-shortener-go/`) and the rest of the lab is unchanged. This
is itself a systems-design lesson: the app is replaceable precisely because the
system communicates over contracts (HTTP, AMQP, SQL), not internals.

Any implementation must provide:

| Contract | Requirement |
|---|---|
| `GET /health` | `200` with JSON `{ "host": "<hostname>", "role": "app" }` |
| `POST /shorten` | body `{ "url": "…" }` → `{ "code": "…" }`; write to primary |
| `GET /:code` | `302` redirect, or `404`; read path (replica when replication and failover active) |
| `POST /jobs` | enqueue to AMQP when queue profile active; `202` |
| `GET /metrics` | Prometheus exposition format (for observability) |
| Env vars | `PORT`, `DATABASE_URL`, `DATABASE_REPLICA_URL`, `AMQP_URL`, `SLOW` |
| `SLOW=1` | artificially delay responses (drives load balancing/circuit breakers fault demos) |
| Logs | structured to stdout; one line per request |

> A Go reference (`apps/url-shortener-go/`) is an **optional contributor exercise**,
> not a parallel guide: the lab ships one canonical runtime so demos stay
> reproducible, and documents the contract so any runtime can satisfy it.

---

## 5. Repository layout (target)

A single Compose file holds the base plus all profile-gated services. Each
service owns a directory (build context + config); stateful-infra config and
init scripts are grouped under `infra/`; everything a module needs to *demonstrate* is
self-contained under `modules/<slug>/`.

```
systems-design/
├── INSTRUCTIONS.MD            # this build spec
├── README.md                 # self-study narrative (to write)
├── LICENSE
├── .gitignore                # ignores certs/, node_modules/, volumes
├── .env.example              # copy to .env; all tunables documented
├── Makefile                  # module targets, scale, chaos, load, reset
├── docker-compose.yml        # base services + profile-gated services
│
├── apps/                     # application code (each leaf builds an image)
│   ├── README.md              # contributor guide: build & wire your own service (§6a)
│   ├── url-shortener/         # Node/Express shortener API (the reference app)
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── server.js             # thin entrypoint: boot + graceful shutdown
│   │   ├── src/                  # MVC: models/ controllers/ routes/ + config, logger, metrics, db, queue, app
│   │   └── proto/                # gRPC contracts (API design)
│   ├── worker/               # generic RabbitMQ consumer, scalable (async queues)
│   ├── graphql-gateway/      # GraphQL facade (API design)
│   └── rate-limiter/         # standalone sharded limiter service (distributed rate limiter capstone)
│
├── gateway/                  # edge / proxy configs
│   ├── nginx/
│   │   ├── nginx.conf            # active config
│   │   └── variants/             # round-robin / ip_hash / least_conn
│   ├── haproxy/
│   │   └── haproxy.cfg           # load balancing contrast (active health checks + stats)
│   ├── edge/                 # edge caching proxy_cache front cache
│
├── infra/                    # stateful-service config + init scripts
│   ├── postgres/             # init SQL, replication config
│   ├── pgbouncer/            # pool config
│   ├── mongo/                # replica-set init script
│   ├── redis/                # cache / rate-limit / geo config
│   ├── rabbitmq/             # queue + DLQ definitions
│   ├── kafka/                # KRaft config, topic bootstrap
│   ├── minio/                # bucket bootstrap (object storage)
│   ├── qdrant/               # vector-store config (vector store)
│   └── consul/               # service-discovery config (service discovery)
│
├── observability/            # observability stack (metrics + traces + logs)
│   ├── prometheus/           # scrape config (metrics)
│   ├── grafana/              # dashboards (queries all three pillars)
│   ├── otel-collector/       # OpenTelemetry pipeline (observability)
│   ├── tempo/                # distributed traces backend (observability)
│   └── loki/                 # centralized logs backend (observability)
│
├── load/                     # k6 load + smoke scripts
│   └── smoke.js              # shorten + redirect via gateway
│
├── scripts/                  # shared shell helpers
│   ├── lib.sh                # demo.sh helpers: step(), pause(), run()
│   └── wait-for.sh           # health/readiness gate
│
└── modules/                  # one folder per lesson; profile name for runnable lessons
  ├── introduction/ … component-selection/
  │   └── README.md         # Foundations (use base profile)
  ├── dns/ … vector-store/
  │   ├── README.md         # Components / Building blocks
  │   └── demo.sh           # guided step-by-step driver
  └── tinyurl/ … distributed-rate-limiter/
    └── README.md         # Capstones: requirements + design writeup
```

> Convention: a runnable lesson's folder name **equals** its Compose profile
> name (`service-discovery/` ↔ `--profile service-discovery`) so
> `make service-discovery` and `modules/service-discovery/` always line up.
> Foundation lessons add no services and run on `base`.

---

## 6. Make targets

- `make base` — start the base system only.
- `make <lesson-profile>` — start base + the services for a runnable lesson.
- Capstones reuse the lesson profiles they need for optional prototypes.
- `make all` — start everything.
- `make scale N=3` — `--scale app=N` to demonstrate horizontal scaling.
- `make chaos` — kill a random container (failure injection).
- `make load` — run the k6 smoke test through the gateway.
- `make reset` — `docker compose down -v` for a clean slate.

---

## 6a. Adding your own service (build, don't just assemble)

The lab is a **platform**, not only a set of demos: once you understand the
components, the capstones expect you to design and run *new* services of your
own. Most building reuses existing profiles, but some capstones (news feed capstone feed, chat capstone
chat, distributed rate limiter capstone rate-limiter) genuinely need a brand-new first-class service. The
workflow is fixed so a new service is never an architectural decision:

1. **Build it against the contract.** Create `apps/<name>/` with a
   `Dockerfile` and your source. There is no scaffolding command — implementing
   the service yourself is part of the exercise. Start with the app contract
   (§4): `/health`, `/metrics`, structured logs, the standard env vars. See
   [apps/README.md](apps/README.md) for the layout to copy and a
   step-by-step guide.
2. **Give it a profile.** Add the service to `docker-compose.yml` under its own
   profile (capstones use semantic capstone profiles); attach it to `backend` (and
   `frontend` only if the gateway must reach it). DBs stay unreachable from the
   host — the DMZ rules still hold.
3. **Wire it in.** Route to it from the Nginx gateway (it is the API gateway),
   or call it service-to-service over `backend`. Reuse infra profiles it needs
  (`redis`, partitioning/sharding nodes, `kafka`) instead of standing up new stores.
4. **Make it observable.** Because it ships `/metrics`, observability's Prometheus
   scrapes it for free — no new wiring to watch it under load.
5. **Prove it.** Add a capstone demo that boots the profile set, drives
   load through it (k6), and breaks it (chaos) like every other module.

> This is the difference between *assembling what exists* and *designing
> something new*. Building against a documented contract + a per-capstone
> profile means "add a service" is a build-and-wire step, so design energy goes
> into the system, not the plumbing.

Each module = a Compose profile (where it adds services) + a semantic
`modules/<slug>/` folder with a `README.md` (concept + what to observe) and a
guided `demo.sh`.

Legend: **Built** = exists in the source repo this spec derives from;
**Designed** = steps defined but no runnable script; **New** = not yet scoped.
Study role: **Core** = required main sequence; **Specialized** = common in real
designs but narrower than the core path; **Advanced** = best studied after the
core mechanisms are understood. Lab-supporting docs such as app contracts,
Docker Compose profiles, Make targets, and exact Grafana provisioning are not
numbered guide topics.

The guide has three tracks:
- **Foundations**: the reasoning layer. Mostly no new services — whiteboard
  concepts plus small scripts that reuse existing demos.
- **Components**: one building block per module, each with a runnable
  failure/observe demo — from name resolution and load
  balancing through data, caching, messaging, coordination, and the
  cross-cutting API / resilience / observability concerns.
- **Capstones**: assemble components into whole systems
  under stated requirements, using an explicit design method.

---

### Foundations (the reasoning layer)

Study first. These close the gap between "I can run a replica" and "I can
reason about a design." None of these require new services unless noted.

#### Introduction — Introduction to systems design *(New)*
- Beginner on-ramp: client, server/service, gateway, database, request path,
  bottleneck, and the idea that a system is parts arranged under constraints.
- Performance vs scalability; latency vs throughput; vertical vs horizontal
  scaling; stateful vs stateless.
- Reuse the scaling `--scale` demo to make "fast for one user vs fast under load"
  concrete.

#### The design method — The design method *(New)*
- A repeatable framework (RESHADED / Primer 4-step): requirements → estimates →
  high-level design → core components → scale & bottlenecks → trade-offs.
- This is the self-assessment rubric used by the capstones. Capture
  **level-based expectations** (mid covers the basics correctly; senior moves
  fast and goes deep in 1–2 areas; staff drives ambiguity and owns trade-offs)
  so capstones can be self-assessed at a target level.

#### Estimation — Back-of-the-envelope estimation *(New)*
- "Latency numbers every programmer should know"; powers-of-two table; QPS,
  storage, and bandwidth math; read:write ratios.
- Seed the worksheet with **modern (2026) numbers**, not 2010-era ones: a tuned
  Postgres handles tens of thousands of TPS and tens of TB; a single Redis does
  100k+ ops/s; a broker does ~1M msgs/s. Using stale numbers makes you shard and
  cache far earlier than reality requires.
- **To implement:** a small `estimate.md` worksheet + a script that measures the
  lab's *actual* latency numbers (cache hit, DB read, cross-container RTT) so
  estimates can be checked against reality.

#### Consistency models — CAP / PACELC & consistency models *(New; reuses replication and failover + leader election)*
- Name and contrast the models the lab already demonstrates: strong, eventual,
  read-your-writes, monotonic reads, causal.
- Map each to a demo: replication and failover replication lag = eventual; replication and failover read-after-write 404 =
  the cost of reading a stale replica; leader election election = CP under partition.
- **To implement:** a `consistency.md` that ties each model to the exact demo
  step that proves it.

#### Availability — Availability & reliability math *(New; reuses observability)*
- The "nines"; availability in series vs parallel; SLI / SLO / SLA and error
  budgets, wired to the observability dashboards.
- **To implement:** an SLO panel + a burn-rate calculation in the Grafana board.

#### When not to scale — When NOT to scale *(New)*
- The counter-lesson the other modules need: premature sharding, caching, and
  queue-everything are anti-patterns. A well-tuned single Postgres + read
  replica goes a long way (see estimation numbers).
- **To implement:** a checklist + a demo that shows the base system comfortably
  handling load *before* any caching/partitioning and sharding machinery is added — "prove you need it
  first."

#### Multi-region DR — Multi-region, disaster recovery & backups *(Advanced; New; reuses replication and failover)*
- Single-region is the default everywhere else in the lab; this module asks the
  next question: what happens when a whole region dies?
- Concepts: **RPO / RTO**; active-passive vs active-active vs multi-primary;
  geo-replication and the latency/consistency cost of crossing regions;
  why **replication is not a backup** (a bad `DELETE` replicates instantly).
- **To implement:** simulate a second "region" with an replication and failover async replica plus
  injected cross-region latency (`tc`/toxiproxy); run a **backup → destroy →
  restore** drill (`pg_basebackup`/`pg_dump`) and measure the achieved RPO/RTO;
  a checklist mapping each lever to a real cloud primitive.

#### Component selection — Choosing the right building block *(New)*
- The selection lens that sits on top of every component: map workload
  characteristics (read:write ratio, consistency need, access pattern, data
  shape, durability) to the right primitive — SQL vs document vs key-value vs
  object store vs vector store vs queue vs log.
- Contrast the components the lab already runs (Postgres replication and failover, Mongo leader election, Redis
  caching, RabbitMQ async queues, Kafka event streaming, MinIO object storage, Qdrant vector store) and name when each is the
  wrong tool.
- **To implement:** a decision checklist + a worked "pick the store" exercise
  tied to the capstones, including when vector retrieval is justified for
  semantic retrieval, recommendations, image similarity, or RAG.

---

### Components

Each component is profile-gated and ships the standard README + `demo.sh`. They
run in book order: name resolution and the system entry point first, then compute and
data, then caching, messaging, coordination, and finally the cross-cutting
API / resilience / observability concerns.

> **Network isolation / DMZ** is *not* a numbered module — it is a property of
> the base stack (the `frontend` / `backend` `internal: true` split, §3–§4). An
> attack/inspect script proving `postgres-primary` is unreachable from the host
> and from `gateway` lives with the base system.

### DNS — DNS & name resolution *(New)*
- A self-contained "mini-internet": root, authoritative, and caching-resolver
  CoreDNS servers on a private `dnsnet`.
- Demo the resolution hierarchy (root referral → authoritative answer), the
  common record types (A, AAAA, CNAME, MX, TXT, SRV), round-robin A records, and
  resolver caching with a TTL countdown.
- **DNS-level load balancing** (round-robin A records) sets up the L4/L7
  balancing contrast that load balancing explores.

### Load balancing — Load balancing (Nginx + HAProxy) *(Built)*
- Contrast DNS-level (see DNS) vs L4 vs L7 balancing.
- Live-swap the Nginx `upstream` block between `round-robin` / `ip_hash` /
  `least_conn` against k6 load.
- Break sticky sessions with an in-memory counter.
- Show Nginx's lack of active health checks via `docker kill` +
  `max_fails` / `fail_timeout`.
- **Nginx vs HAProxy contrast:** an optional `load-balancing-haproxy` profile
  swaps the gateway for HAProxy and runs the *same* traffic through it. The
  lesson is a trade-off, not a tool choice:
  - Why Nginx is the lab default: it's reused as reverse proxy, rate limiter
    (rate limiting), and edge cache (edge caching), so one tool/config language carries half the
    guide. HAProxy does none of the caching/web-server jobs.
  - Why HAProxy is the better *pure* balancer: **active health checks built in**
    (OSS), more algorithms (`leastconn`, `uri`, `hdr`, `random`), and a rich
    runtime stats page.
  - The payoff: kill a replica behind each. Nginx keeps routing to the corpse
    until `max_fails` trips (passive); HAProxy ejects it via active checks and
    shows it on the stats page. This is exactly the gap service discovery (service discovery)
    closes — feel it here first.

### Scaling — Scaling: vertical vs horizontal *(Built)*
- `gateway` + `--scale app=N`; prove distribution via `/health` hostnames.

### Service discovery — Service discovery & health-based routing *(New)*
- Profile adds Consul (or etcd). Services register; the gateway routes by
  healthy registry entries instead of static `upstream`.
- Contrast with load balancing's static Nginx LB; kill an instance and watch it deregister
  (the active health check Nginx lacked in load balancing).

### Replication and failover — Replication & failover *(Built)*
- Profile adds `postgres-replica` (streaming replication; manual `pg_promote()`
  failover).
- Demos: INSERT-on-primary / SELECT-on-replica; replication lag under k6 load;
  read-after-write 404; sync vs async commit; full failover drill.
- **Indexing & query optimization:** run a slow query with no index, read its
  `EXPLAIN (ANALYZE)` plan, add the B-tree index, and watch the plan flip from
  seq-scan to index-scan under k6 load (the single highest-leverage DB fix).

### Leader election — Leader election & replica sets *(Built)*
- Profile adds a 3-node replica set (`mongo1/2/3` + one-shot `mongo-init`).
- Contrast **consensus-based automatic election** vs Postgres's manual failover.

### Partitioning and sharding — Partitioning & sharding *(New)*
- Demonstrate key distribution across N shards; consistent hashing vs modulo;
  rebalancing cost when a node is added/removed.

### Object storage — Object storage *(Specialized; New)*
- Profile adds MinIO (S3-compatible blob store).
- Store uploaded blobs in MinIO, keep metadata in the database, and serve blobs
  through the edge caching edge cache when MinIO acts as the CDN origin.
- Demos: buckets, object keys, private objects, presigned URLs, direct-to-storage
  access, and the application staying off the byte-transfer path.

### Vector store — Vector stores and similarity retrieval *(Specialized; New)*
- Profile adds Qdrant, a local specialized vector database.
- Store embedding vectors with payload metadata and query by nearest-neighbor
  similarity.
- Demos: collection creation, vector upsert, cosine similarity retrieval, metadata
  filtering, and why vector stores are derived indexes rather than sources of
  truth.

### Caching — Caching strategies and invalidation *(New)*
- Profile adds `redis`.
- Cache-aside vs read-through; TTL and eviction; the thundering-herd /
  cache-stampede problem and mitigation; explicit invalidation on write.
- **Probabilistic structures:** a **Bloom filter** to short-circuit lookups for
  codes that definitely don't exist (cache-penetration guard), and
  **HyperLogLog** to count unique visitors per link in O(1) memory.

### Edge caching — Edge caching and CDN model *(Specialized; New)*
- Add an Nginx edge cache (`proxy_cache`) in front of the gateway; cache
  headers, TTL, `stale-while-revalidate`, cache busting, and origin-offload
  measurement.

### Async queues — Asynchronous processing and queues *(Built)*
- Profile adds `rabbitmq` + scalable `worker` containers.
- Async job queue; backpressure via `prefetch(1)`; a dead-letter queue for
  poison messages, retry with exponential backoff, and a job-status record (DB)
  so the async pattern is idempotent and observable.

### Event streaming — Event streaming and replayable logs *(Built)*
- Profile adds Kafka (KRaft mode) + `kafka-ui`.
- Contrast log / replay / consumer-groups vs RabbitMQ's queue-and-delete model:
  partitioning, consumer groups, replay from offset 0.

### Message delivery semantics — Message delivery semantics, outbox & idempotency *(Advanced; New; extends event streaming)*
- Teach delivery semantics first, then implement the **outbox pattern** + consumer-side dedup on Kafka (event streaming) to turn
  at-least-once delivery into effectively-once processing; prove it by replaying.
- Name the dual-write problem explicitly: DB commit and event publish are two
  separate writes unless the event is first stored in the same local transaction.
- Contrast broker delivery guarantees with application processing guarantees.

### Sagas — Distributed transactions & sagas *(Advanced; New; extends async queues + event streaming)*
- Model a multi-service write (e.g. shorten + bill + notify) and show why 2PC is
  fragile; implement a **saga** with compensating actions over RabbitMQ/Kafka.
- Demos: partial failure + compensation; idempotent retries; the dual-write
  problem solved by the transactional outbox.

### API design — API design: REST vs gRPC vs GraphQL *(New)*
- Profile adds a gRPC variant of the `app` plus a GraphQL gateway.
- Contrast contracts, payload size, streaming, versioning, pagination, and
  idempotency semantics against the existing REST shortener.

### Rate limiting — Rate limiting & backpressure *(New)*
- Token-bucket / leaky-bucket limiting at the gateway (Nginx `limit_req`) and at
  the app layer (Redis-backed counters).
- Show `429` behavior, burst handling, and backpressure propagating to the
  queue/worker tier (ties back to async queues's `prefetch`).

### Circuit breakers — Circuit breakers, timeouts & retries *(New)*
- Wrap a flaky downstream dependency with timeout + retry-with-jitter +
  circuit breaker; demonstrate fail-fast vs cascading failure.
- Use the `SLOW`/failure toggles from load balancing to induce the downstream fault.

### Observability — Observability: metrics, logs & traces *(Built; all three pillars)*
- Profile adds `prometheus` + `grafana` + `cadvisor` + `postgres-exporter`
  (metrics), plus `otel-collector` + `tempo` (distributed traces) and `loki`
  (centralized logs) — the **three pillars** in one stack.
- **Metrics:** RED/USE dashboards over the gateway→app→DB path; the duration
  histogram carries `trace_id` exemplars (Prometheus `exemplar-storage`).
- **Traces:** app + worker are OpenTelemetry-instrumented; context propagates
  across HTTP and *through the AMQP message*, so `POST /jobs` is one trace
  spanning app → RabbitMQ → worker (flip `SLOW=1` and find the slow one).
- **Logs:** pino stamps the active `trace_id` on every line; logs ship as OTLP
  through the collector to Loki.
- **Pivot:** Grafana links exemplar → trace (Tempo) → logs (Loki) → back, so one
  slow request is legible across all three signals.
  See `./modules/observability/demo.sh` for the guided walkthrough.

> **CAP / consensus** is covered as a cross-cutting theme by reusing the leader election Mongo
> election demo and the replication and failover Postgres failover drill rather than as a standalone
> profile. consistency models names the models; leader election supplies the election/quorum mechanism.

---

### Capstones (assemble the components)

Each capstone states requirements, runs the design method method, then stands up a
working slice on the lab. Evaluate the design with the design method rubric. These convert "I know
the components" into "I can design a system."

- **TinyURL capstone — TinyURL / Pastebin** *(New)*: formalize the base shortener — capacity
  estimates (estimation), ID scheme trade-offs, read-heavy caching (caching), analytics via Kafka
  (event streaming).
- **news feed capstone — Twitter timeline / news feed** *(New)*: fan-out-on-write vs
  fan-out-on-read, the celebrity/hot-key problem, caching (caching), partitioning/sharding (partitioning and sharding).
- **chat capstone — Chat / WhatsApp** *(New)*: presence, delivery receipts, ordering,
  queues (async queues), websockets through the gateway, at-least-once + dedup (message delivery semantics).
- **distributed rate limiter capstone — Distributed rate limiter as a service** *(New)*: generalize rate limiting
  into a standalone, sharded, Redis-backed limiter with global counters.

> Capstones reuse existing profiles wherever possible; capstones that need a
> brand-new service of your own design (news feed capstone feed, chat capstone chat, distributed rate limiter capstone rate-limiter) get
> their own profile (semantic capstone profiles) and an `apps/<name>/` you build
> against the contract (see §6a). Each adds a semantic module folder with a requirements
> doc, a design writeup, and a `demo.sh` that boots the needed profiles together.

---

## 8. Module-to-profile map

| Lesson | Profile | Adds |
|---|---|---|
| DNS & name resolution | `dns` | `dns-root`, `dns-auth`, `dns-resolver`, `dns-tools` (on `dnsnet`) |
| Load balancing | base | gateway + optional Nginx variants |
| HAProxy load-balancing contrast | `load-balancing-haproxy` | `haproxy` gateway variant (active health checks + stats) |
| Scaling | base | `--scale app=N` |
| Service discovery | `service-discovery` | `consul` (or `etcd`) |
| Replication & failover | `replication-failover` | `postgres-replica` |
| Leader election & replica sets | `leader-election-replica-sets` | `mongo1/2/3`, `mongo-init` |
| Partitioning & sharding | `partitioning-sharding` | `redis` nodes / shard routing |
| Object storage | `object-storage` | `minio` (+ reuse `edge` conceptually) |
| Caching | `caching` | `redis` |
| Edge caching and CDN model | `edge-caching` | `edge` (Nginx proxy_cache) |
| Asynchronous processing and queues | `async-queues` | `rabbitmq`, `worker` |
| Event streaming and replayable logs | `event-streaming` | `kafka`, `kafka-ui` |
| Message delivery semantics | `message-delivery-semantics` | extends `event-streaming`; outbox + dedup |
| Distributed transactions and sagas | `sagas` | extends `async-queues` + `event-streaming`; saga orchestrator |
| API design | `api-design` | gRPC `app` variant, GraphQL gateway |
| Rate limiting and backpressure | `rate-limiting` | `redis` (rate-limit store) |
| Circuit breakers, timeouts and retries | `circuit-breakers` | app-level; reuse SLOW/fault toggles |
| Observability | `observability` | metrics (`prometheus`,`grafana`,`cadvisor`,`postgres-exporter`) + `otel-collector`,`tempo`,`loki` |
| Vector stores and similarity retrieval | `vector-store` | `qdrant` |
| Foundations | base | reasoning layer; reuse component demos where useful |
| TinyURL capstone | compose | reuse `caching`/`event-streaming` |
| News feed capstone | `news-feed` | new feed/fan-out service (+ reuse `caching`/`partitioning-sharding`) |
| Chat capstone | `chat` | new chat service (+ reuse `async-queues`) |
| Distributed rate limiter capstone | `distributed-rate-limiter` | new `rate-limiter` service (+ reuse `rate-limiting` Redis) |

---

## 9. Build backlog (priority order)

1. **load balancing (load balancing)** — full build: `SLOW` toggle, session counter, alternate
   `nginx.conf` variants, demo script.
2. **`demo.sh` scripts** for replication and failover, leader election, event streaming (replication/failover, Mongo
  election, Kafka replay/partitioning) using one consistent guided-demo format.
4. ~~**Grafana dashboards** for observability.~~ *(done — RED dashboard + exemplars)*
5. **New modules caching, rate limiting, circuit breakers, partitioning and sharding, edge caching** — scaffold profiles, READMEs, and demo scripts
   (caching, rate limiting, circuit breakers, sharding, CDN).
6. **Foundations** — author `estimate.md`, `consistency.md`, the SLO
   panel, and the design method design-method rubric (these need no new services and lift
   the lab from "mechanics" to "reasoning").
7. **Extended components (API design, object storage, vector store, message delivery semantics, service discovery, sagas)** — API/gRPC, object storage,
  vector stores, delivery semantics, service discovery, sagas.
8. **Observability depth & resilience** — ~~extend observability with
   traces (OpenTelemetry→Tempo) and logs (Loki)~~ *(done — all three pillars +
   metric→trace→log pivot)*; replication and failover with indexing/EXPLAIN, caching with Bloom/HLL; multi-region DR
   multi-region /DR + backup-restore drill.
10. **Contributor guide for new services** — author `apps/README.md`
    documenting the contract, the reference-app layout to copy, and the
    build-and-wire steps, so capstones can add first-class services (§6a).
11. **Capstones** — TinyURL, feed, chat, rate-limiter-as-a-service.
12. **Top-level `README.md`** tying tracks, modules, make targets, and the
    self-study narrative together for independent use.

---

## 10. Conventions

- **`demo.sh` format:** numbered steps; pause for input between steps
  (`read -p`); echo the command being run and *what to watch for* before running
  it; idempotent where possible.
- **Module README format:** concept summary → prerequisites/profile → run
  command → step-by-step observations → discussion/talking points → cleanup.
- **Naming:** profiles foundation lessons (Foundations, run on `base`), component lessons
  (Components / Building blocks), capstones (Capstones);
  a module's folder name equals its profile name; service names match the
  diagrams in this doc.

---

## 11. Concept → proof matrix

Every concept the reader is expected to leave with, and the exact demo that makes
it observable. "Proven by" is what makes this lab stronger than read-only
courses: the idea is not described, it is reproduced.

| Concept | Proven by |
|---|---|
| Horizontal scaling, statelessness | scaling `--scale` + `/health` hostnames |
| DNS vs L4 vs L7 balancing | load balancing embedded-DNS + Nginx upstream swaps |
| Passive vs active health checks (LB trade-off) | load balancing Nginx `max_fails` vs HAProxy active checks |
| Health checks / passive failure detection | load balancing `max_fails`; service discovery active deregistration |
| Replication & failover (manual) | replication and failover streaming replica + `pg_promote()` |
| Replication lag / eventual consistency | replication and failover lag-under-load; named in consistency models |
| Read-after-write hazard | replication and failover read-after-write 404; named in consistency models |
| Consensus & automatic election | leader election kill-primary election |
| Async processing & backpressure | async queues queue + `prefetch(1)` |
| Log vs queue semantics, replay | event streaming consumer groups + offset-0 replay |
| Caching strategies & invalidation | caching cache-aside + stampede demo |
| Rate limiting | rate limiting `limit_req` + Redis counters → 429s |
| Circuit breakers / timeouts / retries | circuit breakers flaky-dependency wrap |
| Partitioning & sharding | partitioning and sharding key-distribution + rebalancing |
| CDN / edge caching | edge caching `proxy_cache` origin-offload |
| Distributed tracing (request flow) | observability OpenTelemetry → Tempo, hop-by-hop |
| Centralized logs (metric→trace→log) | observability Loki + structured app logs |
| DB indexing & query plans | replication and failover `EXPLAIN` + add-index slow-query demo |
| Probabilistic structures (Bloom/HLL) | caching cache-penetration guard + uniques |
| Multi-region / DR (RPO/RTO) | multi-region DR active-passive + backup/restore drill |
| API design (REST/gRPC/GraphQL) | API design contract + payload contrast |
| Object storage | object storage MinIO |
| Vector stores / similarity retrieval | vector store Qdrant |
| Message delivery semantics / outbox / idempotency | delivery semantics + outbox + dedup replay |
| Service discovery | service discovery Consul register/deregister |
| Distributed transactions / sagas | sagas compensating-action demo |
| Dead-letter queues / retries | async queues DLQ + backoff |
| Estimation & latency numbers | estimation worksheet + measured-latency script |
| CAP / PACELC, consistency models | consistency models mapping to replication and failover/leader election |
| Availability math, SLI/SLO/SLA | availability SLO panel + burn rate |
| The design method + level rubric | design method rubric; applied in TinyURL capstone–distributed rate limiter capstone |
| When NOT to scale (anti-patterns) | when not to scale prove-you-need-it-first demo |
| End-to-end system assembly | TinyURL capstone–distributed rate limiter capstone capstones |

---

## 12. Benchmarked against

This guide was cross-checked against widely used systems-design outlines so the
lab covers the expected scope of a serious systems-design guide. The
lab's differentiator is that each topic is **runnable and reproducible**, not
just read.

- **The System Design Primer** (donnemartin) — topic breadth: CAP, consistency
  & availability patterns, DNS, CDN, LB, DB scaling, caching, asynchronism,
  communication.
- **ByteByteGo — System Design Interview** — the design-method framing and the
  emphasis on requirements/trade-offs (→ design method and capstones).
- **Educative — Grokking Modern System Design** — building-block catalog: DNS,
  LB, key-value store, CDN, sequencer, distributed cache, messaging
  queue / pub-sub, rate limiter, blob store (→ object storage), vector store
  (→ vector store), monitoring (→ observability/availability), plus capstones.
- **MIT 6.5840 / 6.824 (Distributed Systems)** — depth: MapReduce, GFS, Raft,
  linearizability, Spanner, chain replication, Memcached-at-Facebook (→ leader election
  consensus and consistency models; message delivery semantics for idempotent processing).
- **Hello Interview — System Design in a Hurry** — the layered operating model
  (Delivery Framework → Core Concepts → Key Technologies → Patterns);
  level-based expectations (→ design method rubric); "modern numbers"
  (→ estimation); "when not to scale" (→ when not to scale); and specific gaps now covered:
  DLQ/retries (→ async queues), vector retrieval (→ vector store).