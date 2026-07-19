# The Design Method

**Track:** Foundations
**Prerequisites:** none

## Outcome

After this module, you should be able to run a systems-design
discussion in order: clarify requirements, estimate scale, draw a high-level
design, choose components, analyze bottlenecks, and state trade-offs. The output
should be a justified design artifact, not a list of favorite technologies.

## What you will build or run

1. A repeatable design outline that starts from requirements instead of tools.
2. A checklist for scope, workload, data, API, components, bottlenecks, and trade-offs.
3. A worked short-link example that turns requirements into an architecture sketch.
4. A self-assessment rubric you can reuse for the capstone exercises.

## Why this matters

A systems-design discussion - in an interview or a real review - goes badly when
it is improvised: a database choice is made before the QPS is known, or a queue
is added before the workload needs one. A repeatable method keeps the
conversation *driven*: clarify first, estimate, then justify each component
against the numbers. The self-assessment rubric is in [method.md](method.md),
and the capstones reuse it.

## Concept

The method merges the common 4-step framing (RESHADED / "the Primer") into six
explicit steps:

1. **Requirements** - functional + non-functional; clarify scope and the *one*
   metric that matters most (latency? consistency? availability?). Decompose the
   vague problem statement with a **parts-of-speech pass** - literally read the problem
   statement and sort its words into verbs, nouns, and adjectives, because each
   part of speech maps to a different part of the design:
  - **Verbs -> use cases.** "Users *post* tweets, *view* feeds" -> the functional
     requirements (the API surface).
  - **Nouns -> entities & ownership.** "*Users*, *tweets*, *follows*" -> the data
     model and, for each, the *one* service that is its source of truth.
   - **Adjectives -> constraints (and the components they force).** Each adjective
     buys a component: *instant* -> cache / precompute (compute the answer ahead
     of time) / websockets; *reliable* -> retries, idempotency (safe to repeat),
    DLQ (dead-letter queue - a holding area for messages that keep failing);
    *highly available* -> replication, stateless services (keep no per-client
    data, so any copy can serve any request), health checks; *scalable* ->
    partitioning, read replicas, queues. The goal is not to include technology
    for its own sake; each component must be justified by the requirement that
    demands it.
2. **Estimates** - back-of-the-envelope (estimation): QPS, storage, bandwidth,
   read:write ratio.
3. **High-level design** - architecture diagram: clients -> gateway -> services -> data.
4. **Core components** - pick building blocks and *justify each* (use the
   [component-selection](../component-selection/README.md) catalog to choose
   between alternatives).
5. **Scale & bottlenecks** - find the limiting resource, then apply caching (caching),
   replication (replication and failover), sharding (partitioning and sharding), or queues (async queues) **only where the numbers
   demand it** (when not to scale).
6. **Trade-offs** - state what you gave up (consistency, cost, complexity) and why.

## How it works

Each step maps onto a part of this lab, so the method is not abstract: step 2 is
estimation, step 4 uses the component catalog, step 5 is the when not to scale discipline, step 6 is
trade-offs/consistency models vocabulary. Running the components first means that when you *design*, you
are recalling mechanisms that have already been observed in the lab.

### The reference architecture ("master template")

Most read-heavy, write-buffered systems - ones that serve far more reads than
writes, and where writes can be queued and applied slightly later rather than
synchronously - collapse onto one default shape. Reach for it first, then justify
every deviation:

```
          ┌─────────── read path ───────────┐
 client ─▶ gateway ─▶ read service ─▶ cache ──▶ (miss) DB
   │                                            ▲
   │        ┌────────── write path ─────────┐   │
   └──────▶ gateway ─▶ write service ─▶ queue ─▶ workers ─▶ DB + cache
```

- **Write path** - the write service drops the request on a **queue** (async queues) and
  returns immediately; **workers** update the **DB** (source of truth) and
  *warm* the **cache** (pre-populate it with the fresh value so the next read is
  a hit). Buffering absorbs spikes and decouples producer from consumer.
- **Read path** - serve from **cache** (caching); fall back to the **DB** on a miss.
  Reads scale with replicas (replication and failover); the DB stays the source of truth, not the
  **hot path** (the code that runs on every single request, where speed matters
  most).

This one picture ties replication and failover (replication), async queues (queues), and caching (caching) together -
step 4 is largely the decision about which parts of this template the problem requires.

### Level-based expectations

- **Mid** - covers the basics correctly; reasonable components; few gaps.
- **Senior** - moves fast through the basics, then goes **deep in 1–2 areas**
  (hot-key problem, exactly-once, etc.); quantifies trade-offs.
- **Staff** - drives the ambiguity, *sets* the requirements, owns cross-cutting
  trade-offs (cost, org boundaries, failure domains, migration path).

## Run

There's nothing to start - instead, *apply* the method. Start with the worked
example below before trying a full capstone on your own.

### Worked example: design a short-link service

Use the six steps on a deliberately small version of TinyURL:

| Step | Example answer |
|---|---|
| Requirements | Create a short code for a long URL; resolve a code with a fast redirect; tolerate occasional analytics delay. |
| Estimates | Assume 100 writes/sec, 10,000 reads/sec, 5 years of links, and read latency under 100 ms. |
| High-level design | `client -> gateway -> link service -> database`; add a cache on the read path after the database becomes hot. |
| Core components | Relational database for durable mappings, unique ID/code generator for codes, cache for hot redirects, async queue/log for click analytics. |
| Scale and bottlenecks | Reads dominate writes, so cache hot codes first; if the database write/storage ceiling is reached, partition by code. |
| Trade-offs | Cached redirects may be stale briefly after deletion; async analytics may lag; short sequential codes leak approximate volume. |

That is a complete first pass, not a production design. The point is the order:
requirements and numbers force the components. Without the read estimate, adding
a cache is just a guess. Without the write/storage estimate, sharding is not yet
justified.

Now apply the same shape to a capstone:

```bash
./modules/design-method/demo.sh
# Pick a capstone exercise, such as TinyURL or the distributed rate limiter, and work the six steps on paper,
# then build the relevant components and grade yourself with method.md.
```

## How to read the commands

This module has no service to start. Read `./modules/design-method/demo.sh` as a
guided design workshop: it asks for predictions and checkpoints, but the output
you keep is a design write-up. The command-like steps are the six design method
steps, not infrastructure commands.

## How to read the output

The output is a design document. It should include requirements, estimates, a
high-level diagram, component choices, bottleneck analysis, and explicit
trade-offs. If a component appears without a requirement or estimate that needs
it, the design is not justified yet.

For each design choice, write one sentence in this form:

```text
This choice is justified because the requirement or estimate _____ creates pressure on _____.
```

## What to observe

1. Designs improve most at **step 1** - over half of bad designs come from
   skipping requirements clarification.
2. Step 5 should reference **step 2's numbers**; if you add a cache without an
  estimate, that is the when not to scale anti-pattern.
3. The same problem looks different at Mid vs Staff level because the expected
  answer has greater depth, not merely more components.

## What you learned

- Good system design starts by clarifying requirements and constraints.
- Estimates, data model, APIs, and failure modes should shape component choices.
- A design is stronger when it states trade-offs explicitly.
- The same method can be reused for both small services and larger capstones.

## Practice experiments

1. Apply the method to TinyURL capstone in 20 minutes and mark which assumptions are still
  missing.
2. Redo only step 2 with numbers 10x larger and identify which component choices
  change.
3. Grade the result with [method.md](method.md) and write the top two gaps.

## Trade-offs

- The method is a scaffold, not a script - senior+ candidates spend *less* time
  on basics and more on the 1–2 hard parts.
- "Justify each component" is the central rule: every component must justify its
  complexity through a measured estimate or an explicit requirement.

## Next steps

- [Estimation](../estimation/README.md) for sizing requirements.
- [Component selection](../component-selection/README.md) for choosing mechanisms.
- [TinyURL](../tinyurl/README.md) for applying the method to a full design.

## Further reading

- "System Design Primer" (the widely used step framework):
  https://github.com/donnemartin/system-design-primer
- Google SRE Book - "Designing for Reliability" (non-functional requirements):
  https://sre.google/sre-book/
- *Designing Data-Intensive Applications* - Part III ties the components together.

## Cleanup

Nothing to tear down.
