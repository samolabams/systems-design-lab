# Design TinyURL

**Track:** Capstones

## Before you start

Complete or skim these modules first: [The design method](/modules/design-method/),
[Estimation](/modules/estimation/), [Caching](/modules/caching/),
[Database scaling](/modules/database-scaling/), and
[Partitioning and sharding](/modules/partitioning-sharding/). They provide
the vocabulary this capstone expects. For key generation, compare database
sequences, random IDs, hash-based codes, and time-ordered IDs inside the design
document.

## Outcome

After this capstone, you should be able to design a URL shortener
from requirements through estimates, ID generation, storage, caching, analytics,
API shape, and failure modes, using the design method rubric as the evaluation standard.
You should be able to trace both the create path and the redirect path and name
which operation must stay fastest under load.

## What you will build or run

1. A design artifact for a URL-shortening system.
2. An API contract for creating and resolving short links.
3. A data model for codes, long URLs, ownership, expiry, and analytics.
4. A scaling and failure plan for redirects, collisions, storage, and hot links.

## Why this matters

The URL shortener has been the reference app throughout the lab. This capstone
steps back and designs it deliberately by applying the design method end-to-end and
using the relevant components. It is the introductory capstone because the domain
is already familiar; the focus is the *process*, not domain novelty.

The design is a useful interview problem because the surface area is tiny but
the hidden choices are real: key generation, collision handling, cache behavior,
abuse controls, expiry, analytics, and hot-link protection. The short URL is only
the product shape; the engineering problem is making redirects fast and durable
without letting optional analytics slow them down.

> This is a paper exercise, not a coding task. The deliverable is a design doc.
> The running [`apps/url-shortener/`](https://github.com/samolabams/systems-design-lab/tree/main/apps/url-shortener) is here as a
> *reference implementation for comparison* — not something to extend or produce
> as the deliverable here.

## Concept

Work the [design method](/modules/design-method/) against this app and grade
the result with the design method self-assessment rubric:

1. **Requirements** — create-short-link, redirect, basic analytics; functional vs
   non-functional (latency, availability, scale).
2. **Estimates** — reuse the [estimation back-of-envelope](/modules/estimation/) math:
   reads ≫ writes, storage for N links, QPS at peak.
3. **Key-generation scheme** — compare counter+base62, hash-based, random, and
   time-ordered IDs, including collision handling.
4. **Read path** — cache hot links with [caching](/modules/caching/); the
   redirect must be fast and cheap.
5. **Analytics** — emit click events to [event streaming](/modules/event-streaming/)
   so counting never slows the redirect.
6. **Scale & resilience** — replicas ([scaling](/modules/scaling/)), DB read replicas
   ([replication and failover](/modules/replication-failover/)), and sharding
   ([partitioning and sharding](/modules/partitioning-sharding/)) if the
   *keyspace* (the theoretical set of possible keys) is exhausted or if *data
   volume* and query load demand it.

## How it works

The existing URL-shortener app is a reference implementation for this design
exercise. Use the running app only for comparison: the deliverable is a design
document that explains requirements, estimates, APIs, data model, read/write
paths, cache strategy, analytics flow, and failure behavior.

## Task

Apply the [design method](/modules/design-method/) end-to-end and write
a short design document. There is no required runnable demo. For optional
prototyping, start the referenced module profiles and drive the existing app
through the proposed design. A strong answer:

1. Picks an ID scheme that produces short, collision-free keys at the target rate.
2. Serves hot-link redirects from cache, barely touching the origin DB.
3. Streams click events to Kafka without adding latency to the redirect.
4. Evaluates cleanly against the design method rubric, with the gaps stated explicitly.

Use this design-document outline:

| Section | What to include |
|---|---|
| Requirements | create link, resolve link, custom aliases, expiry, abuse controls, latency and availability targets |
| Estimates | read/write QPS, storage for links and analytics, hot-link assumptions, redirect latency budget |
| API contract | `POST /shorten`, `GET /{code}`, optional analytics/admin endpoints, error cases |
| Data model | link mapping, owner, expiry, status, analytics event, indexes and uniqueness constraints |
| Read/write path | code creation, redirect, cache lookup, database fallback, analytics emission |
| Scaling plan | app replicas, cache, read replicas, partitioning/sharding trigger, hot-link handling |
| Failure modes | duplicate code, deleted/expired link, cache stale entry, analytics lag, database outage |
| Trade-offs | short vs opaque IDs, sync vs async analytics, freshness vs speed, cost vs complexity |

Grade the result with the same dimensions as [method.md](/modules/design-method/method.md):
requirements, estimates, API/data model, component choices, scaling bottlenecks,
consistency, operability, and explicit trade-offs.

## How to read the task

This is not asking for a product pitch or a list of tools. Read it as an
architecture exercise: define requirements, estimate load, choose the ID and data
model, draw read/write paths, then justify every component with a number or
requirement.

## How to read the output

A strong design document makes the redirect path obvious and short. The write
path should create durable link metadata, the read path should favor cache and
database lookup by code, and analytics should be asynchronous. If the design does
not state collision handling, cache invalidation, and abuse controls, it is not
complete yet.

Read the artifact as two timelines. The create timeline must prove a code is
unique before it is returned. The redirect timeline must prove the code maps to a
valid long URL quickly, even when analytics, cache misses, or stale entries are
present. Anything not required for the redirect should be off the critical path.

## What to observe

1. **The redirect path is the hot path** - it should be short, cache-friendly, and easy to scale.
2. **ID generation is a product and capacity decision** - short, guessable, random, and custom aliases have different costs.
3. **Analytics should not slow redirects** - click events belong on an asynchronous path.
4. **Every component needs a reason** - the design should tie cache, replicas, queues, and sharding to estimates or requirements.

For each path, write one sentence in this form:

```text
This path stays correct/fast because _____ happens before/after _____.
```

## What you learned

- A shortener design is mostly about read-heavy routing, ID generation, and durable mappings.
- Code generation choices affect collisions, predictability, and storage shape.
- Redirect latency matters because every extra hop is user-visible.
- Caching and analytics add useful behavior but change consistency and write volume.

## Practice experiments

1. Redesign for custom aliases and explain what new uniqueness and abuse checks
   appear.
2. Increase traffic by 100x and decide whether Partitioning and sharding is now justified.
3. Require real-time analytics and explain what changes in the Kafka/aggregation
   path.

## Trade-offs

- **ID scheme** — sequential is short and dense but *leaks volume* (an outsider
  can tell how many links exist, and guess neighbouring ones) and is guessable;
  random/hash hides it but is longer and risks collisions (two inputs producing
  the same key).
- **Custom aliases** — user-chosen slugs add a uniqueness check and abuse surface.
- **Analytics freshness** — async counting (Kafka) means click counts are
  *eventually consistent* (the displayed count trails reality by a moment, consistency models).
- **Cache invalidation** — links rarely change, so caching is easy here; note why
  that isn't true for every app.

## Next steps

- Revisit the key-generation section of this capstone for code/id strategy.
- [Caching](/modules/caching/) for hot redirects.
- [API gateway](/modules/api-gateway/) for the public request path.

## Further reading

- Alex Xu, *System Design Interview*, ch. "Design a URL Shortener".
- [design method](/modules/design-method/) and its self-assessment rubric.
- Use only the canonical sources linked from the referenced modules.

## Cleanup

Only if you spun up profiles to prototype:

```bash
make reset
```
