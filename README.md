# Systems Design Lab

A systems-design guide with practical examples for learning how real-world system components fit together. The guide repo combines short lessons with runnable examples and guided demos to demonstrate how systems work in the real world.

## Quick navigation

- [Quick start](#quick-start)
- [Table of contents](#table-of-contents)
- [How the guide works](#how-the-guide-works)
- [System requirements](#system-requirements)
- [Common commands](#common-commands)
- [Guide structure](#guide-structure)
- [Architecture overview](#architecture-overview)
- [Application contract](#application-contract)
- [Repository structure](#repository-structure)
- [Validate your changes](#validate-your-changes)
- [Safety and security](#safety-and-security)

## What is Systems Design Lab?

Systems Design Lab is a local practice environment for core systems-design ideas: DNS, load balancing, gateways, scaling, databases, caching, queues, event streaming, replication, sharding, observability, object storage, vector search, and related topics.

Each lesson starts by introducing the concept then proceeds to practical implementation / demo. All components have been configured to run locally via docker.

## Quick start

```bash
cp .env.example .env
make base
curl http://localhost:8080/api/health
```

Then open [modules/README.md](modules/README.md) and pick a module.

Most runnable modules follow this pattern:

```bash
make <module-name>
./modules/<module-name>/demo.sh
```

For example:

```bash
make caching
./modules/caching/demo.sh
```

Use `AUTO=1` to run many demos without pauses:

```bash
AUTO=1 ./modules/caching/demo.sh
```

## Table of contents

| Order | Area | Lesson |
|---:|---|---|
| 1 | Foundations | [Introduction to systems design](modules/introduction/README.md) |
| 2 | Foundations | [The design method](modules/design-method/README.md) |
| 3 | Foundations | [Estimation](modules/estimation/README.md) |
| 4 | Foundations | [When not to scale](modules/when-not-to-scale/README.md) |
| 5 | Foundations | [Choosing the right building block](modules/component-selection/README.md) |
| 6 | Foundations | [Consistency models](modules/consistency-models/README.md) |
| 7 | Foundations | [Availability and reliability math](modules/availability/README.md) |
| 8 | Core request path | [DNS and name resolution](modules/dns/README.md) |
| 9 | Core request path | [Load balancing](modules/load-balancing/README.md) |
| 10 | Core request path | [API gateway](modules/api-gateway/README.md) |
| 11 | Core request path | [Scaling: vertical vs horizontal](modules/scaling/README.md) |
| 12 | Core request path | [Service discovery](modules/service-discovery/README.md) |
| 13 | Data layer | [Databases](modules/databases/README.md) |
| 14 | Data layer | [Database scaling](modules/database-scaling/README.md) |
| 15 | Data layer | [Replication and failover](modules/replication-failover/README.md) |
| 16 | Data layer | [Leader election and replica sets](modules/leader-election-replica-sets/README.md) |
| 17 | Data layer | [Partitioning and sharding](modules/partitioning-sharding/README.md) |
| 18 | Async and workflows | [Async queues](modules/async-queues/README.md) |
| 19 | Async and workflows | [Event streaming and replayable logs](modules/event-streaming/README.md) |
| 20 | Async and workflows | [Message delivery semantics, outbox, and idempotency](modules/message-delivery-semantics/README.md) |
| 21 | Async and workflows | [Distributed transactions and sagas](modules/sagas/README.md) |
| 22 | Performance and delivery | [Caching](modules/caching/README.md) |
| 23 | Performance and delivery | [Edge caching and CDN model](modules/edge-caching/README.md) |
| 24 | Performance and delivery | [Object storage](modules/object-storage/README.md) |
| 25 | Interfaces and protection | [API design](modules/api-design/README.md) |
| 26 | Interfaces and protection | [Rate limiting and backpressure](modules/rate-limiting/README.md) |
| 27 | Interfaces and protection | [Circuit breakers, timeouts, and retries](modules/circuit-breakers/README.md) |
| 28 | Operations | [Observability](modules/observability/README.md) |
| 29 | Operations | [Multi-region disaster recovery and backups](modules/multi-region-dr/README.md) |
| 30 | Specialized retrieval | [Vector stores and similarity retrieval](modules/vector-store/README.md) |
| 31 | Capstone | [Design TinyURL](modules/tinyurl/README.md) |
| 32 | Capstone | [Design a news feed](modules/news-feed/README.md) |
| 33 | Capstone | [Design a chat system](modules/chat/README.md) |
| 34 | Capstone | [Design a distributed rate limiter](modules/distributed-rate-limiter/README.md) |

## How the guide works

Each module is a small lab:

- **Outcome** states what the module should make you understand.
- **What you will build or run** previews the concrete activity.
- **Concept** defines the idea without tying it to one vendor.
- **How it works** maps the idea to this repo.
- **Run / Task** gives commands or a design exercise.
- **How to read the output** explains what the command output proves.
- **What you learned** recaps the durable takeaways.
- **Practice experiments** give small variations to test understanding.
- **Trade-offs** names what the component improves and what it costs.
- **Next steps** points to related modules.

## System requirements

- Docker Desktop or Docker Engine with Compose v2
- `make`
- `curl`
- `bash`
- Node.js for a few local scripts

Optional but useful:

- `jq` for JSON output
- `k6` is not required locally; load tests run through the Docker image in `make load`

Ports used by common profiles:

| Service | Port |
|---|---:|
| Gateway | 8080 |
| URL-shortener app direct port | 3000 |
| RabbitMQ UI | 15672 |
| Kafka UI | 8081 |
| Grafana | 3001 |
| MinIO console | 9001 |
| Qdrant | 6333 |
| HAProxy stats | 8404 |

## Common commands

```bash
make help                         # list targets
make base                         # start the base request path
make scale N=3                    # scale stateless app replicas
make load                         # run the k6 smoke load through the gateway
make <module-name>                # start services for one module
make validate-profile PROFILE=dns # validate one runnable module
make validate                     # validate runnable modules sequentially
make reset                        # stop containers and remove volumes
```

## Guide structure

Start with foundations, then move along the request path, then data systems, then workflows and operations. Specialized retrieval modules and capstones come after the core mechanisms.

The module index is [modules/README.md](modules/README.md). It includes the full lesson list, suggested tracks, and a glossary.

## Architecture overview

The conceptual base path is:

```text
client -> edge gateway -> application service -> data access layer -> durable store
```

The concrete base lab implements that path as:

```text
curl/browser -> Nginx gateway -> URL-shortener app -> database access layer -> relational database
```

The concrete lab uses PgBouncer for connection pooling and Postgres for the
relational database. Most lessons describe the pattern first and name the exact
service only when a command, configuration file, or database-specific lesson
requires it.

The guide does not treat Postgres as the default answer for every system. It is the durable relational store used by this local lab because it gives a clear, inspectable source of truth. Other modules add Redis, RabbitMQ, Kafka, MongoDB, MinIO, Qdrant, Consul, HAProxy, and the observability stack when those components are the right tool for the lesson.

## Application contract

The URL-shortener app provides a small shared contract used across modules:

| Method/path | Meaning |
|---|---|
| `GET /api/health` | app health and instance identity |
| `GET /api/metrics` | Prometheus metrics |
| `POST /api/shorten` | create or return a short link for `{ "longUrl": "https://..." }` |
| `GET /api/links/:code` | resolve a short code and return a `302` redirect |
| `POST /api/jobs` | enqueue background work when the async queue profile is active |

`POST /api/shorten` returns `201` when a mapping is new and `200` when the same
long URL already exists. The response includes both `code` and `shortUrl`.
The gateway exposes API routes under `/api/...` and also keeps root-level
short-code redirects (`GET /:code`) for compatibility with earlier modules.

## Repository structure

```text
apps/                  runnable application services
infra/                 reusable infrastructure configs
modules/               concept modules and guided demos
scripts/               shared demo helpers and validation scripts
docker-compose.yml     base stack plus module profiles
Makefile               entry points for running and validating labs
```

## Validate your changes

Validation keeps this guide trustworthy. The lessons are not only text; many of
them depend on Docker profiles, shell scripts, local links, and demo output. Run
focused checks while editing so small mistakes are caught early, then run the
full validator before larger releases or structural changes.

Use focused validation while editing:

```bash
bash -n modules/<module>/demo.sh
make validate-profile PROFILE=<module>
docker compose config --quiet
```

Use full validation before a larger release:

```bash
make validate
```

`make validate` starts each runnable module, runs its demo where applicable, and resets the environment between modules.

## Safety and security

This is a local lab. Do not expose the services directly to the public internet. Credentials in Compose files and examples are for local development only.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and local-lab safety notes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for module conventions and validation expectations.

## License

See [LICENSE](LICENSE).
