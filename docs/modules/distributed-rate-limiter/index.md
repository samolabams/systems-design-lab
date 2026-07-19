# Design A Distributed Rate Limiter

**Track:** Capstones

## Before you start

Complete or skim these modules first: [The design method](/modules/design-method/),
[Estimation](/modules/estimation/), [API gateway](/modules/api-gateway/),
[Rate limiting](/modules/rate-limiting/), [Caching](/modules/caching/),
and [Partitioning and sharding](/modules/partitioning-sharding/). They provide
the vocabulary this capstone expects.

## Outcome

After this capstone, you should be able to design a distributed
rate limiter that enforces global quotas across replicas while balancing
accuracy, latency, storage, failure behavior, and abuse resistance. You should
be able to explain why local counters are insufficient and what failure policy
the product wants when the shared limiter is unavailable.

## What you will build or run

1. A design artifact for a rate limiter that works across more than one app instance.
2. A choice of key, quota window, counter storage, and enforcement point.
3. A failure-mode analysis for stale counters, hot keys, and shared dependency outages.
4. A trade-off summary for accuracy, latency, and availability.

## Why this matters

[Rate limiting](/modules/rate-limiting/) limited requests at a single gateway.
Real systems run many gateways or app replicas, so a limit of "100 req/min per
user" must be enforced globally across all of them. Distributed limiters need
shared counters or coordinated state; otherwise each node can admit up to its
local quota, multiplying the intended global limit.

The core question is not just which algorithm to use. It is where authority
lives. If every gateway decides alone, the system is fast but inaccurate. If one
shared store decides every request, the system is accurate but adds latency and
a new dependency. Most real designs deliberately choose a point between those
two extremes.

## Concept

Apply the [design method](/modules/design-method/):

- **Why distributed** — per-node counters let a user get `N × (#nodes)` requests;
  the counter must be **shared** (Redis) so all nodes see one total.
- **Algorithms** — *fixed window* (count per fixed clock interval — simple, but
  allows a double burst across a boundary), *sliding window* (count over the
  trailing N seconds — smoother, more state), *token bucket / leaky bucket*
  (tokens refill at a steady rate up to a cap; spend one per request — allows
  bursts up to the cap, then throttles to the refill rate).
- **Global counters** — atomic `INCR` (add 1) / `EXPIRE` (set a TTL), or a small
  **Lua script** (run several Redis commands as one atomic step), keep the count
  consistent across callers; sharding spreads hot keys.
- **Sharding & hot keys** — partition counters by key
  ([partitioning and sharding](/modules/partitioning-sharding/)); a single very *hot key* (one key taking a
  huge share of traffic) may need local pre-aggregation.
- **Fail-open vs fail-closed** — if the limiter store is down, do you allow
  (fail-open) or block (fail-closed) requests? Usually fail-open for availability
  — same stance as caching/rate limiting.
- **Distribution** — return the standard HTTP `429 Too Many Requests` plus a
  `Retry-After` header (telling the client how long to wait) and rate-limit
  headers so clients back off.

## How it works

Enforcing limits across distributed nodes requires a design for shared state,
consistency, sharding, and failure handling. The design document should define
the limiting key, algorithm, shared state model, sharding strategy, client
contract, and failure behavior before choosing implementation details.

## Task

Apply the [design method](/modules/design-method/) end-to-end and write
a short design document. There is no required runnable demo. For optional
prototyping, stand up a Redis-backed limiter service and drive it from multiple
callers. A strong answer:

1. Has two instances sharing Redis enforce **one** combined limit, not two separate
   ones.
2. Returns `429` + `Retry-After` past the budget, then resets after the window.
3. Compares algorithms (fixed vs sliding vs token bucket) and their burst behaviour.
4. Fails open when the store is unreachable (configurable).

Use this design-document outline:

| Section | What to include |
|---|---|
| Requirements | quota subjects, limits, burst behavior, headers, latency budget, abuse cases |
| Estimates | requests/sec, unique keys, hot-key distribution, counter writes/sec, storage per window |
| API contract | check/admit request, return `429`, `Retry-After`, remaining quota, reset time |
| Algorithm | fixed window, sliding window, token bucket, or hybrid; exactness and storage cost |
| State model | Redis keys, TTLs, Lua/atomic operations, sharding key, local pre-aggregation if used |
| Scaling plan | multiple gateways/app replicas, shared counters, hot-key mitigation, multi-region behavior |
| Failure modes | Redis outage, slow limiter, stale counters, clock skew, abusive tenant, retry storm |
| Trade-offs | accuracy vs latency, fail-open vs fail-closed, local cache vs global correctness |

Grade the result with the same dimensions as [method.md](/modules/design-method/method.md):
requirements, estimates, API/data model, component choices, scaling bottlenecks,
consistency, operability, and explicit trade-offs.

## How to read the task

Read this as a distributed state problem. The limiter must make decisions across
multiple gateway or app instances, so the key question is where the counter lives
and how exact it must be. Algorithm choice, consistency, and failure behavior are
the core design axes.

## How to read the output

A strong design document names the limiting key, the algorithm, the shared state
store, the headers returned to clients, and the fail-open/fail-closed policy. It
should also explain hot-key behavior and what happens if Redis or the limiter
service becomes slow.

Read the artifact as an admission decision. For one incoming request, identify
the key, the window or bucket state, the atomic operation, the response headers,
and the fallback path when shared state cannot answer. If two gateways can admit
more than the stated global limit without the design noticing, the design is not
distributed enough.

## What to observe

1. **The counter must be shared** - per-node counters do not enforce a global quota.
2. **Algorithm choice shapes user experience** - fixed windows, sliding windows, and token buckets fail differently.
3. **Hot keys are likely** - a single abusive user or tenant can concentrate load on one shard.
4. **Failure policy is product policy** - fail-open and fail-closed protect different priorities.

For each enforcement choice, write one sentence in this form:

```text
This limiter is more accurate/available because it stores the decision state in _____.
```

## What you learned

- Distributed rate limiting is harder than local counters because requests hit many replicas.
- The rate-limit key and window define what behavior is actually controlled.
- Centralized counters improve consistency but add latency and dependency risk.
- A good limiter design states what happens during partial failure.

## Practice experiments

1. Redesign for per-IP anonymous limits and per-user authenticated limits at the
  same time.
2. Replace fixed window with token bucket and explain the burst behavior change.
3. Add regional gateways and decide whether limits must be globally exact.

## Trade-offs

- **Accuracy vs cost** — sliding-window/log is precise but stores more state; fixed
  window is low-cost but allows boundary bursts.
- **Consistency vs latency** — a strictly global count needs a round trip to shared
  state on every request; some designs trade exactness for speed (local + sync).
- **Hot keys** — one extremely active key can bottleneck a shard; pre-aggregate
  locally then flush.
- **Fail-open vs fail-closed** — availability vs protection when the limiter itself
  is degraded.

## Next steps

- [Rate limiting](/modules/rate-limiting/) for the runnable local mechanism.
- [Caching](/modules/caching/) for shared fast state trade-offs.
- [API gateway](/modules/api-gateway/) for boundary enforcement.

## Further reading

- Alex Xu, *System Design Interview*, ch. "Design a Rate Limiter".
- Cloudflare, "How we built rate limiting capable of scaling to millions of
  domains": https://blog.cloudflare.com/counting-things-a-lot-of-different-things/
- Referenced modules: [rate limiting](/modules/rate-limiting/),
  [partitioning and sharding](/modules/partitioning-sharding/).

## Cleanup

Only if profiles were started for prototyping:

```bash
make reset
```
