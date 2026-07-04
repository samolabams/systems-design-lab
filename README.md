# Systems Design Lab

A runnable systems-design guide for learning how real backend components fit together. The repo combines short concept modules, Docker Compose profiles, and guided demos so each idea can be observed locally instead of only described in a diagram.

## Quick navigation

- [Quick start](#quick-start)
- [First study session](#first-study-session)
- [What you can explore](#what-you-can-explore)
- [How the guide works](#how-the-guide-works)
- [System requirements](#system-requirements)
- [Common commands](#common-commands)
- [Guide structure](#guide-structure)
- [Architecture overview](#architecture-overview)
- [Application contract](#application-contract)
- [Repository structure](#repository-structure)
- [Validation](#validation)
- [Safety and security](#safety-and-security)

## What is Systems Design Lab?

Systems Design Lab is a local practice environment for core systems-design ideas: APIs, gateways, DNS, load balancing, scaling, databases, caching, queues, event streaming, replication, sharding, observability, object storage, vector retrieval, and capstone designs.

The lessons are concept-first and implementation-second. Each module explains the general idea, maps it to local containers, gives commands to run, describes how to read the output, and names the trade-offs.

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

## First study session

A good first pass is:

1. [Trade-offs and vocabulary](modules/tradeoffs/README.md)
2. [The design method](modules/design-method/README.md)
3. [Estimation](modules/estimation/README.md)
4. [API gateway](modules/api-gateway/README.md)
5. [Databases](modules/databases/README.md)
6. [Caching](modules/caching/README.md)
7. [Async queues](modules/async-queues/README.md)
8. [Observability](modules/observability/README.md)
9. [Design TinyURL](modules/tinyurl/README.md)

That path moves from vocabulary to a complete design artifact while keeping every step tied to a runnable local system.

## What you can explore

| Area | Modules |
|---|---|
| Foundations | trade-offs, design method, estimation, availability, when not to scale |
| Request path | DNS, load balancing, API gateway, scaling, service discovery |
| Interfaces and protection | API design, rate limiting, circuit breakers |
| Data systems | databases, database scaling, replication and failover, leader election, partitioning and sharding, consistency models |
| Performance and delivery | caching, edge caching, scaling, async queues, event streaming, message delivery semantics, sagas |
| Operations | observability, multi-region disaster recovery |
| Specialized storage and retrieval | object storage, vector store |
| Capstones | TinyURL, news feed, chat, distributed rate limiter |

## How the guide works

Each module is a small lab:

- **Outcome** states what the module should make you able to explain.
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
curl/browser -> Nginx gateway -> URL-shortener app -> PgBouncer -> Postgres primary
```

The guide does not treat Postgres as the default answer for every system. It is the durable relational store used by this local lab because it gives a clear, inspectable source of truth. Other modules add Redis, RabbitMQ, Kafka, MongoDB, MinIO, Qdrant, Consul, HAProxy, and the observability stack when those components are the right tool for the lesson.

## Application contract

The URL-shortener app provides a small shared contract used across modules:

| Method/path | Meaning |
|---|---|
| `GET /api/health` | app health and instance identity |
| `GET /api/metrics` | Prometheus metrics |
| `POST /api/shorten` | create a short link |
| `GET /:code` | resolve a short code and redirect |
| `POST /api/jobs` | enqueue background work when the async queue profile is active |

The gateway exposes API routes under `/api/...` and redirects short-code lookups through the same public entry point.

## Repository structure

```text
apps/                  runnable application services
infra/                 reusable infrastructure configs
modules/               concept modules and guided demos
scripts/               shared demo helpers and validation scripts
docker-compose.yml     base stack plus module profiles
Makefile               entry points for running and validating labs
```

## Validation

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
