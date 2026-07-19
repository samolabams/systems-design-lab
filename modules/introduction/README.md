# Introduction To Systems Design

**Track:** Foundations
**Prerequisites:** none

## Outcome

After this module, you should understand systems design as reasoning
about system parts under constraints, not as memorizing architecture diagrams.
You should be able to explain the difference between latency and throughput,
vertical and horizontal scaling, stateful and stateless services, bottlenecks,
and trade-offs.

## What you will build or run

1. An understanding of latency, throughput, availability, consistency, and state.
2. A small base-stack run that shows how replica count affects request latency.
3. Short trade-off statements you can reuse in later modules.
4. A foundation for explaining why a design choice is justified.

## Why this matters

This is the first systems-design lesson, so it starts with the basics. A system
is a set of components that work together to serve users under constraints.
Those components might include clients, gateways, services, databases, caches,
queues, networks, and monitoring tools. Systems design is the process of
deciding how those parts fit together, how data moves between them, and how the
system behaves when traffic grows, dependencies fail, or requirements change.

A good design is not just a diagram. It explains the trade-offs behind the
choices: what the system optimizes for, what it gives up, and why those choices
fit the problem in front of it. Calling something "scalable" when you mean
"fast", or "available" when you mean "consistent", leads to weak design
arguments. This module pins down the vocabulary so the rest of the guide has
precise language to reason with.

## Concept

Before the trade-offs, name the basic shape:

- **Client.** A process or device that initiates a request for a service. A
  client can be a browser, mobile app, command-line script, batch job, or another
  service.
- **Server / service.** A process that exposes a capability over a network or
  local interface, accepts requests, performs work, and returns responses or
  side effects.
- **Gateway.** An entry point that receives client traffic and applies shared
  concerns such as routing, TLS termination, authentication, rate limiting,
  request shaping, or protocol translation before forwarding traffic inward.
- **Database.** A system for storing, indexing, querying, and updating data with
  durability guarantees, so important state can survive process or machine
  restarts.
- **Request path.** The ordered sequence of components involved in serving one
  operation, such as client -> gateway -> service -> data store -> response.
- **Bottleneck.** The resource or component that limits overall system
  performance or capacity. Improving a non-bottleneck component usually has
  little effect on end-to-end behavior.

Then four distinctions do most of the work:

- **Performance vs scalability.** Performance is how fast the system is for a
  given workload ("fast for one user"); *scalability* is its ability to cope with
  increased load - to stay fast as users or data grow. A system can be fast and
  unscalable (one large in-memory server) or slow but scalable (adds capacity
  linearly). They are different goals with different fixes.
- **Latency vs throughput.** Latency is time per operation; throughput is
  operations per second. Optimizing one often hurts the other - batching raises
  throughput but adds latency; per-request work lowers latency but caps
  throughput.
- **Vertical vs horizontal scaling.** Vertical scaling means using a larger
  server; horizontal scaling means using more servers. Vertical scaling is
  simpler but bounded by machine size and creates a single point of failure.
  Horizontal scaling raises the capacity ceiling but requires stateless services
  and a load balancer (scaling).
- **Stateful vs stateless.** A stateless service keeps no per-client data in its
  own memory, so any replica can serve any request (scaling). Stateful services need
  replication (replication and failover), sharding (partitioning and sharding), or sticky routing (load balancing `ip_hash`).

## How it works

The lab is built so these abstractions are physically demonstrable. The app is
*stateless* (all durable state lives outside the app process), which is exactly
what lets you run N identical replicas behind one gateway. "Scale" here is literally `--scale app=N`:
the same application code running on more containers. Latency-vs-throughput
trade-offs are observed by holding the code fixed and changing only the load
(VUs - *virtual users*, the simulated concurrent clients driven by k6) and the
replica count.

## Run

```bash
make base
./modules/introduction/demo.sh
make scale N=1 && make load     # baseline: fast for one user / light load
make scale N=3 && make load     # same code, 3x compute - observe p95 under load
```


## How to read the commands

Read `./modules/introduction/demo.sh` as the guided version of the commands
below it. It pauses before each observation so you can predict what should
happen and then connect the output to the vocabulary.

Read `make scale N=1` and `make scale N=3` as changing only the number of app
replicas. The application code, gateway, database, and load test stay the same.
That isolates the effect of horizontal scaling.

Read `make load` as a repeatable traffic generator. It creates concurrent virtual
users so latency and throughput can be observed under pressure.

## How to read the output

Focus on request status codes, requests per second, and p95 latency. Status `200`
or `302` means the request succeeded. **p95 latency** means the 95th percentile:
95% of requests finished at or below that time, and the slowest 5% took longer.
Higher p95 under the same load means the system is slower for the tail of users.
Lower p95 after adding replicas means horizontal scaling helped the app tier.

For each run, write one sentence in this form:

```text
This result shows _____ because status/QPS/p95 changed from _____ to _____.
```

## What to observe

1. At **N=1** with light load, p95 latency is low - the system is *fast*.
2. At **N=1** with ramped VUs, p95 climbs - fast, but not *scalable* yet.
3. At **N=3**, p95 recovers under the same load - that is *scalability* (more
  servers, unchanged code), only possible because the app is stateless.

## What you learned

- System design is a series of trade-offs under requirements and constraints.
- Latency, throughput, availability, consistency, cost, and complexity interact.
- A design choice is incomplete unless it says what it improves and what it risks.
- Precise vocabulary makes later modules easier to reason about.

## Practice experiments

1. Run `make scale N=2` and predict whether p95 lands between `N=1` and `N=3`.
2. Hit `/health` several times and identify which app host served each request.
3. Explain why adding app replicas would not help if the database is the bottleneck.

## Trade-offs

- Which services are truly stateless? Hidden state, such as in-memory caches,
  sticky sessions, or local files, breaks horizontal scaling.
- Vertical scaling is often the correct *first* move - simpler, no distribution
  cost - until a measured ceiling forces horizontal (see when not to scale).
- More replicas do not help if a *shared* dependency, such as the database, is
  the bottleneck; that motivates replication and failover/caching/partitioning and sharding.

## Next steps

- [Estimation](../estimation/README.md) for adding numbers to trade-offs.
- [Consistency models](../consistency-models/README.md) for a common distributed trade-off.
- [The design method](../design-method/README.md) for applying the vocabulary.

## Further reading

- Martin Kleppmann, *Designing Data-Intensive Applications* - Ch. 1
  (reliability, scalability, maintainability). https://dataintensive.net/
- "Latency Numbers Every Programmer Should Know" (interactive):
  https://colin-scott.github.io/personal_website/research/interactive_latency.html
- The Twelve-Factor App (statelessness, processes): https://12factor.net/processes

## Cleanup

```bash
make scale N=1
make reset
```
