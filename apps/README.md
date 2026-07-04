# Apps — adding application services

This is **supporting lab documentation**, not a numbered systems-design module.
It defines the service contract used by the runnable modules and capstone
prototypes.

This folder holds the application code. Each leaf folder builds one container
image.

- [url-shortener](url-shortener) — the reference app (Node/Express). The
  canonical implementation of the **app contract** and the reference structure
  for new services.
- [worker](worker) — a generic RabbitMQ consumer that drains the `jobs` queue
  (async queues: async processing & backpressure). It is not tied to the
  URL-shortener — any service can enqueue work for it.

The lab functions as a **platform** for component study and integration, not
only as a set of demonstrations. After the components are understood, the
capstones (news feed capstone feed, chat capstone chat, distributed rate limiter capstone rate-limiter) require new services designed
against the same contract. There is intentionally no scaffolding command:
implementing the service against the contract is part of the exercise.

## The contract comes first, the language second

The lab treats a service as a **contract**, not a language. Any runtime —
Node, Python, Go, Rust, Java — is a valid service as long as it satisfies the
contract below. observability's Prometheus scrapes it the same way regardless of
language, and the gateway load-balances it without special handling.

Every service must provide:

| Endpoint | Requirement |
|---|---|
| `GET /health` | `200` with JSON `{ "host": "<hostname>", "role": "<role>" }` |
| `GET /metrics` | Prometheus exposition format (text) |

Plus two conventions:

- **Config from the environment.** Read `PORT` (default `3000`) and a `ROLE`
  label, and any backing-service URLs (`DATABASE_URL`, `AMQP_URL`, …) from env.
  Never hard-code addresses or ports (twelve-factor: config lives in the
  environment).
- **Structured logs to stdout.** One JSON object per line, e.g.
  `{"ts":"…","host":"…","event":"request","method":"GET","path":"/health","status":200}`.
  The container runtime collects stdout; do not write log files.

The reference app extends this same contract with `/shorten`, `/:code`, and
`/jobs` — see the root [README](../README.md#application-contract).

## How the reference app is laid out

Use this structure as a reference. It keeps each concern in one place and remains
small enough to inspect directly. A simpler service can omit layers it does not
need; for example, a service with no database does not need `models/` or
`migrations/`.

```
url-shortener/
├── Dockerfile            # small, non-root, with a /health HEALTHCHECK
├── package.json
├── knexfile.js           # migration CLI config (only if you use a database)
├── migrations/           # versioned schema changes (Knex)
├── server.js             # thin entrypoint: boot dependencies + graceful shutdown
└── src/
    ├── config.js         # read every env var once, export typed values
    ├── logger.js         # structured logging (pino) to stdout
    ├── metrics.js        # Prometheus registry + per-request RED middleware
    ├── db.js             # connection pools (write->primary, read->replica) + migrations
    ├── queue.js          # optional AMQP client with auto-reconnect
    ├── app.js            # Express assembly: middleware + routes
    ├── models/           # domain entities (data + behaviour), persistence-free
    ├── repositories/     # database access — the only place that knows the tables
    ├── services/         # application logic — orchestrate models, repos & cache
    ├── controllers/      # thin request handlers — validate, call a service, respond
    └── routes/           # URL -> controller table
```

The split is MVC with repository and service layers: **models** are the domain
entities (data and behaviour, no SQL), **repositories** own all database access,
**services** hold the application logic (orchestrating models, repositories and
the cache), **controllers** stay thin (validate input, call a service, shape the
response), and **routes** map URLs to controllers. The entrypoint (`server.js`)
only starts things up and shuts them down.

## Steps to add a service

1. **Create the folder.** Make `apps/<name>/` with at minimum a `Dockerfile`,
   your source, and (for Node) a `package.json`. Implement `/health` and
   `/metrics` first — that alone makes it a valid lab citizen.
2. **Write the Dockerfile.** Keep `EXPOSE 3000`, a `HEALTHCHECK` that probes
   `/health`, a non-root `USER`, and a `CMD` that starts your server. Use a
   small base image.
3. **Handle `SIGTERM`.** Drain gracefully — stop accepting new connections,
   finish in-flight work, close DB/broker clients, then exit. Docker sends
   `SIGTERM` on `stop`/scale-down and waits ~10s before `SIGKILL`, so keep any
   failsafe timer under that.
4. **Give it a profile.** Add the service to [../docker-compose.yml](../docker-compose.yml)
   under its own semantic profile. Attach it to the
   `backend` network — and to `frontend` only if the gateway must reach it.
   Databases stay unreachable from the host; the DMZ rules still hold.
5. **Wire it in.** Route to it from the Nginx gateway (the API gateway), or call
   it service-to-service over `backend`. Reuse infra profiles it needs
  (`redis`, partitioning/sharding nodes, `kafka`) instead of standing up new stores.
6. **Make it observable.** Because the service exposes `/metrics`, observability's
  Prometheus can scrape it without additional instrumentation work.
7. **Demonstrate it.** Add `modules/<slug>/demo.sh` that starts the profile set,
  drives load through it with k6, and exercises a failure scenario in the same
  format as the other modules.

This separates *assembling existing components* from *designing a new service*.
Adding a service is a build-and-wire exercise, so design attention can remain on
the system behavior rather than on incidental setup details.
