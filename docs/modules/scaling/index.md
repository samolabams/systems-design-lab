# Scaling: Vertical Vs Horizontal

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand scaling as a concrete
capacity decision rather than a generic instruction to "make it bigger." With
no prior scaling knowledge, you should be able to explain:

1. What scaling means: increasing a system's ability to handle load.
2. The difference between vertical scaling and horizontal scaling.
3. Why horizontal scaling requires stateless application replicas.
4. Why a load balancer or gateway is needed once more than one replica exists.
5. Why scaling the app tier can expose bottlenecks in shared dependencies such as databases.
6. How to use `make scale N=...` to change app replica count in this lab.
7. What evidence proves that more than one app replica exists and can serve the
    same request.

## What you will build or run

1. A base service scaled across multiple app replicas.
2. Requests that reveal which replica handled each call.
3. A load or capacity comparison between one instance and several instances.
4. A distinction between vertical scaling, horizontal scaling, and shared dependency pressure.

## Why this matters

**Scaling is the act of increasing a system's capacity to handle more load.** Load can mean more users, more requests per second, larger payloads, more background jobs, more stored data, or more concurrent connections. A system that works for one user can still fail under many users if one component reaches its limit.

There are two basic ways to scale compute capacity:

- **Vertical scaling** - make one machine bigger: more CPU, more memory, faster disk, or more network capacity.
- **Horizontal scaling** - add more machines or replicas: several smaller copies share the work.

Vertical scaling is simple because the application still runs in one place. It is often the fastest first move when a single server is underpowered. But it has a ceiling: eventually the machine cannot be made larger, or the larger machine becomes too expensive.

Horizontal scaling raises the ceiling by adding more replicas. It is the dominant pattern for stateless web and API services because replicas can be added and removed as traffic changes. But it has stricter requirements: requests must be routable to any replica, state must live outside the process, and shared dependencies must be able to handle the extra traffic.

The concept is independent of any one orchestrator or web framework. The lab uses
Docker Compose and the URL-shortener app tier as one concrete implementation of
horizontal scaling.

## Scaling map

Scaling is not one move. It is a diagnosis loop: identify the pressure, choose
the smallest useful change, measure again, and only then add more machinery.

| Pressure | First move | Later move |
|---|---|---|
| CPU-bound app process | profile code, tune hot path, scale vertically | horizontal app replicas, autoscaling |
| App request volume | add stateless replicas behind a gateway | autoscaling and better load balancing |
| Too many database connections | add or tune connection pooling | reduce chatty queries, split read/write paths |
| One slow database query | inspect query plan, add/change index | remodel access pattern |
| Read-heavy database load | cache hot reads or add read replicas | CDN/edge caching, read/write split |
| Write-heavy database load | batch writes, queue background work | partitioning/sharding |
| Dataset too large for one node | archive cold data, partition by access pattern | sharding and rebalancing |
| Uneven traffic or hot keys | identify hot key or tenant | key splitting, replication, special-case routing |
| Traffic bursts | queue work, apply backpressure | rate limiting and load shedding |
| Dependency failures | timeouts and retries with jitter | circuit breakers and graceful degradation |
| Unknown bottleneck | add metrics, logs, traces, and load tests | capacity planning and SLO-driven scaling |

Use this map as a compass for the rest of the guide. scaling proves app-tier
replicas. [Database scaling](/modules/database-scaling/) applies the
same diagnosis loop to the data tier. Later modules prove the specific tools:
replication, leader election, sharding, caching, queues, rate limiting, circuit
breakers, and observability.

## Concept

A single app instance gives one place for requests to go:

```text
client -> gateway -> app-1
```

Horizontal scaling creates several identical app instances:

```text
client -> gateway -> app-1
                  -> app-2
                  -> app-3
```

The app instances are called **replicas**. Each replica runs the same code and should be able to handle the same request. The gateway or load balancer decides which replica receives each request.

The key vocabulary:

- **Load** - the amount of work the system must handle, usually measured as requests per second, concurrent users, jobs per minute, or bytes processed.
- **Capacity** - how much load the system can handle while staying within acceptable latency and error limits.
- **Vertical scaling** - increasing the resources of one machine or process.
- **Horizontal scaling** - increasing the number of machines, processes, or replicas.
- **Replica** - one running copy of a service.
- **Stateless service** - a service that does not keep required per-client state in local memory. Any replica can serve the next request.
- **Shared dependency** - a component used by all replicas, such as a database, cache, queue, or external API.

## Why statelessness matters

Horizontal scaling works cleanly only when the app tier is stateless.

A stateless app keeps durable state outside the process. In this lab, URL data lives in the database, not in one app container's memory. That means any app replica can receive a request and still read or write the same underlying data.

If a service stores required session data in local memory, horizontal scaling becomes fragile:

```text
request 1 -> app-1 stores session in memory
request 2 -> app-2 does not have that session
```

That is why production systems usually move session state, cache state, and durable data into shared systems rather than relying on a single app process.

## Vertical vs horizontal scaling

| Strategy | What changes | Strength | Limitation |
|---|---|---|---|
| Vertical scaling | one machine gets bigger | simple, fewer moving parts | hard ceiling, larger blast radius, often expensive |
| Horizontal scaling | more replicas are added | higher ceiling, better fault tolerance | requires statelessness, routing, and shared dependencies |

A common path is to use both. Start with a reasonably sized machine, then scale horizontally when one instance is no longer enough or when availability requires multiple replicas.

## What scaling does not solve

Scaling the app tier does not automatically fix every bottleneck. More app replicas can create more pressure on shared dependencies:

```text
more app replicas -> more database work -> the database becomes the bottleneck
```

This is why the guide later covers connection pooling, replication, caching, sharding, queues, and backpressure. Scaling one tier can move the bottleneck to another tier.

Scaling also does not fix inefficient code, slow queries, hot keys, lock contention, external API limits, or a design that stores required state in one local process.

## How it works

The base stack starts one app service behind the gateway:

```text
host curl -> gateway -> app replica(s) -> database access layer -> relational database
```

Docker Compose can run several copies of the same app service:

```bash
make scale N=3
```

That command expands the app tier to three replicas. The gateway still receives traffic on `localhost:8080`, and the app replicas remain internal. The gateway routes `/api/health` to the app's internal `/health` endpoint, which returns the container hostname, so repeated requests show which replica answered.

The important files and commands are:

| Item | Role in the lab | What to inspect |
|---|---|---|
| [Makefile](https://github.com/samolabams/systems-design-lab/tree/main/Makefile) | Defines `make scale` and `make health-loop` | `docker compose up -d --scale app=$(N)` |
| [infra/gateway/nginx/nginx.conf](https://github.com/samolabams/systems-design-lab/blob/main/infra/gateway/nginx/nginx.conf) | Gateway in front of app replicas | `proxy_pass`, Docker DNS resolver, `/api/*` routes |
| [apps/url-shortener/src/controllers/healthController.js](https://github.com/samolabams/systems-design-lab/blob/main/apps/url-shortener/src/controllers/healthController.js) | Returns replica identity | `{ "host": "...", "role": "app" }` |
| [modules/load-balancing](/modules/load-balancing/) | Explains traffic distribution | load balancing strategies and health checks |
| [modules/api-gateway](/modules/api-gateway/) | Explains the public entry point | explicit gateway route mapping |

## Run

Run these commands from the repository root:

```bash
```

The output should end with:

```text
systems-design
```

Start the base stack:

```bash
make base
```

Run the guided scaling demo:

```bash
./modules/scaling/demo.sh
```

You can also run the steps manually:

```bash
make scale N=1
make health-loop
make scale N=3
make health-loop
make scale N=5
make health-loop
```

## How to read the commands

Scaling the app tier:

```bash
make scale N=3
```

| Part | Meaning |
|---|---|
| `make scale` | run the Makefile target that changes app replica count |
| `N=3` | desired number of app replicas |
| `docker compose up -d --scale app=3` | the underlying Compose operation |

Probing replica identity:

```bash
make health-loop
```

This sends repeated requests to the gateway. Each response includes the app container hostname. Seeing more than one hostname proves more than one replica answered during that sample. Seeing one hostname repeatedly does not mean scaling failed; it can mean the gateway/DNS path stayed pinned during a short sample. load balancing and service discovery go deeper on balancing and service membership.

## How to read the output

A health response looks like this:

```json
{"host":"systems-design-app-2","role":"app"}
```

The important field is `host`. If repeated gateway responses show only one host,
traffic is reaching one replica during that sample. If repeated gateway responses
show multiple hosts, traffic is reaching multiple replicas. The stronger scaling proof
is simpler: Docker is running multiple app containers, and each container can
answer the same `/health` request from inside the Docker network.

Do not expect every short sample to be perfectly even. DNS caching, gateway behavior, and timing can make a small sample look uneven. Use several requests before drawing a conclusion.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves the app tier has multiple replicas because repeated `/api/health` responses show different hostnames.
```

## What to observe

1. **Baseline** - with `N=1`, repeated `/api/health` requests should show one app hostname.
2. **Scale out** - with `N=3`, Docker runs several app containers from the same image.
3. **Replica interchangeability** - each app container can answer the same `/health` request, which is why stateless replicas can share work.
4. **Gateway sample** - repeated `/api/health` requests may show several app hostnames, or one repeated hostname if the gateway/DNS path is cached during the sample.
5. **Scale farther** - with `N=5`, more replicas exist, but short samples may not show perfect distribution.
6. **Scale down** - reducing to `N=2` removes replicas without changing the public gateway address.
7. **Same code, more copies** - horizontal scaling changes the number of running app processes, not the app code.
8. **Shared dependency ceiling** - more app replicas can create more database work and more pressure on the data tier.

## What you learned

- Vertical scaling makes one machine bigger; horizontal scaling adds more copies.
- Stateless services are easier to scale horizontally.
- Scaling app replicas can move the bottleneck to the database, cache, or queue.
- Scaling should follow a measured pressure point.

## Practice experiments

After the guided demo, change one thing at a time and predict the effect before running traffic again:

1. **Compare replica counts.** Run `make scale N=1`, `N=3`, and `N=5`; record how many distinct hostnames appear in `make health-loop`.
2. **Increase the sample size.** Send 30 or 60 `/api/health` requests and count hostnames.
3. **Run load.** Compare `make load` at `N=1` and `N=3`; watch whether latency changes.
4. **Watch containers.** Run `docker compose ps app` after each scale command and match containers to health responses.
5. **Find the next bottleneck.** Ask what shared dependency receives more traffic when app replicas increase.

## Trade-offs

- **Vertical scaling is simpler but finite.** A bigger server is easy to reason about, but it has a practical and financial ceiling.
- **Horizontal scaling raises the ceiling but adds coordination.** More replicas require routing, health checks, service discovery, and shared state.
- **Statelessness is the price of admission.** Store required per-client state in local memory and the next request may land on a replica that does not have it.
- **Linear scaling has a ceiling.** Throughput grows only until a shared dependency, such as a database, cache, queue, or external API, becomes the bottleneck.
- **More replicas increase dependency pressure.** App replicas can create more database work; without connection management, the data tier can exhaust capacity before the app tier is saturated.
- **Scaling can hide inefficient design.** Adding replicas may postpone a problem without fixing slow queries, large payloads, hot keys, or lock contention.

## Next steps

- [Load balancing](/modules/load-balancing/) for distributing traffic across replicas.
- [Database scaling](/modules/database-scaling/) for shared dependency pressure.
- [When not to scale](/modules/when-not-to-scale/) for avoiding unnecessary scale work.

## Further reading

- The Twelve-Factor App, "Processes" and "Concurrency": https://12factor.net/concurrency
- Microsoft Azure Architecture Center, "Autoscaling guidance": https://learn.microsoft.com/azure/architecture/best-practices/auto-scaling
- AWS Well-Architected Framework, "Reliability pillar": https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html
- *Designing Data-Intensive Applications*, Chapter 1 - scaling out vs scaling up.

## Cleanup

```bash
make scale N=1
make reset
```
