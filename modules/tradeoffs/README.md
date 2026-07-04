# What is a system? Trade-offs & vocabulary

**Track:** Foundations
**Prerequisites:** none

> **Status:** Runnable - uses the base lab stack to connect vocabulary to measured behavior.

## Outcome

After this module, you should understand systems design as reasoning
about system parts under constraints, not as memorizing architecture diagrams.
You should be able to explain the difference between latency and throughput,
vertical and horizontal scaling, stateful and stateless services, bottlenecks,
and trade-offs.

## What you will build or run

1. A vocabulary map for latency, throughput, availability, consistency, and state.
2. Small examples that show why improving one property can hurt another.
3. A set of trade-off statements you can reuse in later modules.
4. A foundation for explaining why a design choice is justified.

## Why this matters

This is the first systems-design lesson, so it starts from the beginning: a
system is a set of parts that work together to serve users under constraints.
Those parts might be clients, gateways, services, databases, caches, queues,
networks, and monitoring tools. Systems design is deciding how those parts fit
together so the result is fast enough, reliable enough, correct enough, secure
enough, and affordable enough for the problem in front of you.

Every systems-design decision is a trade-off. Most bad designs come from using a
word loosely — calling something "scalable" when you mean "fast", or
"available" when you mean "consistent". This module pins down the vocabulary so
the rest of the guide has precise language to reason with. Get the words
right and the design arguments get much shorter.

## Concept

Before the trade-offs, name the basic shape:

- **Client.** The caller: a browser, mobile app, another service, or a script.
- **Server / service.** Code that accepts requests and returns responses.
- **Gateway.** The front door that receives traffic and routes it inward.
- **Database.** The durable source of truth for state that must survive restarts.
- **Request path.** The chain a request follows: client -> gateway -> service ->
  data store -> response.
- **Bottleneck.** The slowest or most saturated part of that chain; scaling a
  different part will not help much.

Then four distinctions do most of the work:

- **Performance vs scalability.** Performance is how fast the system is for a
  given workload ("fast for one user"); *scalability* is its ability to cope with
  increased load — to stay fast as users or data grow. A system can be fast and
  unscalable (one large in-memory server) or slow but scalable (adds capacity
  linearly). They are different goals with different fixes.
- **Latency vs throughput.** Latency is time per operation; throughput is
  operations per second. Optimizing one often hurts the other — batching raises
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
*stateless* (all state lives in Postgres), which is exactly what lets you run N
identical replicas behind one gateway. "Scale" here is literally `--scale app=N`:
the same application code running on more containers. Latency-vs-throughput
trade-offs are observed by holding the code fixed and changing only the load
(VUs — *virtual users*, the simulated concurrent clients driven by k6) and the
replica count.

## Run

```bash
pwd
make base
make scale N=1 && make load     # baseline: fast for one user / light load
make scale N=3 && make load     # same code, 3x compute — observe p95 under load
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

Read `make scale N=1` and `make scale N=3` as changing only the number of app
replicas. The application code, gateway, database, and load test stay the same.
That isolates the effect of horizontal scaling.

Read `make load` as a repeatable traffic generator. It creates concurrent virtual
users so latency and throughput can be observed under pressure.

## How to read the output

Focus on request status codes, requests per second, and p95 latency. Status `200`
or `302` means the request succeeded. Higher p95 under the same load means the
system is slower for the tail of users. Lower p95 after adding replicas means
horizontal scaling helped the app tier.

## What to observe

1. At **N=1** with light load, p95 latency (the latency 95% of requests come in
  *under* — the slow tail that averages can hide) is
   low — the system is *fast*.
2. At **N=1** with ramped VUs, p95 climbs — fast, but not *scalable* yet.
3. At **N=3**, p95 recovers under the same load — that is *scalability* (more
  servers, unchanged code), only possible because the app is stateless.

## What you learned

- System design is a series of trade-offs under requirements and constraints.
- Latency, throughput, availability, consistency, cost, and complexity interact.
- A design choice is incomplete unless it says what it improves and what it risks.
- Precise vocabulary makes later modules easier to reason about.

## Practice experiments

1. Run `make scale N=2` and predict whether p95 lands between `N=1` and `N=3`.
2. Hit `/health` several times and identify which app host served each request.
3. Explain why adding app replicas would not help if Postgres is the bottleneck.

## Trade-offs

- Which services are truly stateless? Hidden state, such as in-memory caches,
  sticky sessions, or local files, breaks horizontal scaling.
- Vertical scaling is often the correct *first* move — simpler, no distribution
  cost — until a measured ceiling forces horizontal (see when not to scale).
- More replicas do not help if a *shared* dependency, such as the single
  Postgres instance, is the bottleneck; that motivates replication and failover/caching/partitioning and sharding.

## Next steps

- [Estimation](../estimation/README.md) for adding numbers to trade-offs.
- [Consistency models](../consistency-models/README.md) for a common distributed trade-off.
- [The design method](../design-method/README.md) for applying the vocabulary.

## Further reading

- Martin Kleppmann, *Designing Data-Intensive Applications* — Ch. 1
  (reliability, scalability, maintainability). https://dataintensive.net/
- "Latency Numbers Every Programmer Should Know" (interactive):
  https://colin-scott.github.io/personal_website/research/interactive_latency.html
- The Twelve-Factor App (statelessness, processes): https://12factor.net/processes

## Cleanup

```bash
make scale N=1
make reset
```
