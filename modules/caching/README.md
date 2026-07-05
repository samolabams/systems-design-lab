# Caching strategies & invalidation

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand caching as a general performance,
scalability, and resilience mechanism rather than an informal shortcut for
making things faster. You should be able to explain:

1. What a cache does: it stores a temporary copy of data so repeated reads can be
  served with lower latency and less load on the origin.
2. Why caches are common in read-heavy workloads.
3. What a cache hit and cache miss mean.
4. How cache-aside works: the application checks the cache first, falls back to
  the origin on a miss, then populates the cache.
5. Why cached data can become stale and how TTLs bound staleness.
6. What cache invalidation means and why mutable data makes it harder.
7. Why a cache should offload the source of truth, not replace it.

## What you will build or run

1. A cache-backed read path that shows cache hits, misses, and invalidation behavior.
2. Repeated requests that demonstrate lower database pressure after data is cached.
3. A stale-data scenario that makes freshness trade-offs visible.
4. A comparison between application caching and edge caching responsibilities.

## Why this matters

**Caching is a standard system design technique for reducing latency and origin
load on repeated reads.** Many systems have a working set of hot data that is
requested far more often than it changes: a user profile, a product page, a
session, a feature flag, a feed page, a rate-limit counter, or the result of an
expensive computation. Without a cache, the system repeats the same origin lookup
or computation for every request.

A cache keeps hot data in a low-latency storage layer, often memory. Instead of
querying the source of truth for every repeated read, the system can serve from a
cached copy when the consistency requirements allow it.

Caching is part of the critical path for many high-traffic systems: feeds,
profiles, product pages, sessions, API responses, feature flags, rate-limit
counters, and computed recommendations. A well-designed cache improves response
time, throughput, and origin protection. A poorly designed cache can return
stale data, trigger a thundering herd of origin requests, or become an accidental
second source of truth.

The concept is independent of any one cache product. The lab uses the local
URL-shortener stack and Redis as one concrete implementation so hits, misses,
TTL, origin offload, cache-aside loading, and the boundary between cached data
and durable database state are visible.

Caching does not make the database unnecessary. It answers a latency and load
question. The database still owns durable state; the cache holds derived or
copied entries that can be dropped and rebuilt.

## Concept

A cache is a **temporary, low-latency copy** of data that already exists in an
authoritative system. The authoritative system is often called the **origin** or
**source of truth**. The cache is allowed to forget data because the origin can
rebuild the response.

The basic lookup path has two possible outcomes:

```text
cache hit  -> the key is present, so the system serves the cached value
cache miss -> the key is absent, so the system reads from the origin
```

Those two terms appear throughout caching discussions:

- **Cache hit** - the requested key is present in the cache.
- **Cache miss** - the requested key is absent from the cache, so the system must
  read from the origin.
- **Origin** - the authoritative place the data comes from.
- **TTL** - time-to-live, a countdown after which a cached entry expires.
- **Eviction** - removing cached entries when capacity is limited or an eviction
  policy selects them.
- **Invalidation** - deleting or updating a cached copy when the source data
  changes.
- **Staleness** - the cache returns an older value than the source of truth.
- **Hit ratio** - the fraction of cache lookups that are hits.
- **Miss penalty** - the extra latency and origin load paid when a lookup misses.

The cache is fast because it usually stores entries in memory and performs
key-based lookups. That is also its limitation: a cache is not durable storage
for data that must survive failure. If a cache loses an entry, the system should
be able to read or recompute the value from the origin and repopulate the cache.

The most common caching pattern is **cache-aside**, also called lazy loading:

```text
application reads cache by key
if hit: return cached value
if miss: read origin, populate cache, return value
```

Other patterns exist:

| Pattern | Who loads the cache? | Good fit | Trade-off |
|---|---|---|---|
| Cache-aside | application code | explicit control, common service pattern | application handles miss logic |
| Read-through | cache layer | simpler application reads | requires cache loader integration |
| Write-through | cache layer or application writes cache and origin together | recently written data is cache-warm | write latency and coupling increase |
| Write-behind | cache accepts write, origin updates later | low write latency | data-loss and ordering risk increase |

This lab intentionally shows a hybrid: redirects use cache-aside on reads, while
newly created short links warm the cache during the write path. That lets one
module show both the common read-miss flow and the reason a system might choose
write-through-style warming for data that is likely to be read immediately.

Two control mechanisms make caching useful rather than dangerous:

- **TTL-based expiration bounds staleness.** A cached value expires after a
  limited time, so stale data cannot live forever just because nobody invalidated
  it.
- **Cache invalidation handles writes.** If data changes before the TTL expires,
  the system must update or delete the cached copy. Immutable data is easier
  because it does not change after creation.

Caching can also fail under load in a specific way: a **cache stampede** or
**thundering herd** happens when a hot key expires and many requests miss at the
same time. Instead of one request refreshing the value, many requests hit the
origin together. Common mitigations include jittered TTLs, request coalescing,
per-key locks, leases, or stale-while-revalidate.

## How it works

The general caching roles are represented by local containers in this lab:

| General role | Lab implementation |
|---|---|
| client-facing service | URL-shortener app |
| cache | Redis |
| origin / source of truth | durable database |
| observable behavior | hit/miss counters |

A URL shortener is a useful cache example because one short code may be created
once but redirected many times. If every redirect goes to the database, the
database spends connections, CPU, and disk I/O answering the same lookup again
and again. With caching enabled, a repeated redirect can read from Redis instead
of the database:

```text
client -> gateway -> app -> Redis
                         -> database only on cache miss
```

The profile starts Redis next to the base stack. The important request path is
the redirect handler in the URL-shortener app:

```text
GET /:code
  -> read Redis key link:<code>
  -> on hit, return 302 with the cached URL
  -> on miss, read the database, set Redis key with a TTL, return 302
```

The helper code lives in [apps/url-shortener/src/cache.js](../../apps/url-shortener/src/cache.js).
That file wraps Redis access so the rest of the app can use cache operations
such as `get`, `set`, and `del` without knowing the Redis protocol.

Writes also **warm** the cache. When `POST /shorten` creates a new mapping, the
app stores the new `link:<code>` value in Redis as well as the database. That means
the first redirect after creation can already be a cache hit. This is useful for
the lab, and it is a deliberate write-through-style choice, but the source of
truth is still the database.

The cache client is **fail-open**. If Redis is not configured or is temporarily
unavailable, cache operations become no-ops and the app falls back to the
database path. That keeps Redis from becoming a hard dependency for correctness.
The system may become slower and put more load on the database, but it should still
answer from the origin.

The app exports cache metrics for observability:

```text
cache_requests_total{result="hit"}
cache_requests_total{result="miss"}
```

Those counters let you calculate cache hit ratio and see whether repeated reads
are being served from Redis or falling through to the database. Later, observability uses the
same idea in the observability stack.

When reading this module, keep these layers separate:

```text
application code -> decides when to check, set, or delete cache entries
Redis            -> stores temporary key-value entries with TTLs
database         -> stores durable link mappings
metrics          -> show hit and miss behavior
```

If the behavior is confusing, first ask which layer should own the answer. If
the answer must be durable, it belongs in the database. If the answer is a repeated
read that can be rebuilt, it may belong in Redis.

## Run

Run these commands from the repository root:

```bash
pwd
```

The output should end with:

```text
systems-design
```

Start the caching profile:

```bash
make caching
```

Then run the guided demo:

```bash
./modules/caching/demo.sh
```

The demo pauses between steps. At each step, first read the question, then read
the command, then inspect the output. The goal is not to memorize Redis commands;
the goal is to connect each command to one caching idea.

To run without pauses:

```bash
AUTO=1 ./modules/caching/demo.sh
```

## How to read the commands

Most commands in this module have one of three shapes.

An HTTP request through the gateway:

```bash
curl -s -o /dev/null -w 'status=%{http_code} time=%{time_total}s\n' http://localhost:8080/<code>
```

Read that as:

| Part | Meaning |
|---|---|
| `curl` | make an HTTP request |
| `-s` | quiet mode |
| `-o /dev/null` | ignore the response body |
| `-w ...` | print selected measurements, such as status and time |
| `http://localhost:8080/<code>` | ask the gateway to resolve the short code |

A Redis inspection command:

```bash
docker compose --profile caching exec -T redis redis-cli GET link:<code>
```

Read that as:

| Part | Meaning |
|---|---|
| `docker compose --profile caching exec -T redis` | run a command inside the Redis container |
| `redis-cli` | open the Redis command-line client |
| `GET link:<code>` | read the cached value for one short-code key |

A metrics query:

```bash
curl -s http://localhost:8080/metrics | grep cache_requests_total
```

Read that as: ask the app for Prometheus-format metrics, then show only the
cache hit and miss counters.

Changing one part changes the question. `GET link:<code>` asks Redis for the
cached URL. `TTL link:<code>` asks how many seconds remain before the cached
entry expires. `INFO stats` asks Redis for aggregate cache statistics such as
`keyspace_hits` and `keyspace_misses`.

## How to read the output

A Redis value such as this:

```text
https://example.com/cached
```

means the cache currently has the URL for that `link:<code>` key. The app can
redirect without reading the database.

A TTL output such as this:

```text
57
```

means the key will expire in 57 seconds. A few special TTL values are common:

| Output | Meaning |
|---|---|
| positive number | seconds remaining before expiry |
| `-1` | key exists but has no expiry |
| `-2` | key does not exist |

Metric lines such as these:

```text
cache_requests_total{result="hit"} 51
cache_requests_total{result="miss"} 1
```

mean the app has served 51 cache hits and 1 cache miss since the process started.
The exact numbers depend on what traffic has already run in your local lab.

Redis stats such as these:

```text
keyspace_hits:50
keyspace_misses:1
```

mean Redis itself has answered many successful key lookups and only a small
number of missing ones. A rising hit count is evidence that repeated reads are
being offloaded from the database.

## What to observe

1. **A warmed key can hit immediately** - `POST /shorten` writes the durable row
   and also stores the cache entry, so the first redirect can avoid the database.
2. **A cold key misses once** - deleting the Redis key forces the next redirect
  to read the database and repopulate Redis.
3. **Repeated reads become hits** - hammering the same short code increases the
   hit counters because the app keeps finding `link:<code>` in Redis.
4. **TTL counts down** - `TTL link:<code>` shows the cached copy is temporary.
5. **The origin is protected** - after the cache is warm, repeated redirects can
   be served without repeated database reads.

## What you learned

- Caching stores copies of hot data to reduce repeated work and dependency pressure.
- A cache hit is fast because it avoids the slower source of truth.
- Invalidation and freshness are the hard parts of cache design.
- Caches improve read paths but can introduce stale reads and operational complexity.

## Practice experiments

1. Delete the Redis key for a known short code and predict the next request's
  hit or miss behavior.
2. Compare TTL before and after waiting a few seconds.
3. Explain what would need to change if short-link destinations were mutable.
4. Decide which metric would prove the cache is reducing database reads.

## Trade-offs

- **Caching trades freshness for speed.** Immutable data, like this lab's short
  links, is the easy case. Mutable data needs an invalidation strategy and a
  staleness budget (consistency models).
- **A cache is memory, not a database.** Size it, set eviction policy, and never
  store data that cannot be reconstructed from the source of truth.
- **A cache can hide problems.** Add caching when measurement or estimation (estimation)
  says repeated reads are the pressure. Premature caching adds consistency work
  before the system needs it (when not to scale).
- **Misses can become a spike.** If many hot keys expire together, the database
  can receive a sudden burst of reads. Use jitter, request coalescing, or stale
  serving when that risk matters.
- **Fail-open is safer for correctness but not free.** If Redis is down, this
  lab falls back to the database. That preserves correctness, but latency and
  database load can rise quickly.

## Next steps

- [Edge caching](../edge-caching/README.md) for caching closer to users.
- [Databases](../databases/README.md) for the source-of-truth role.
- [Consistency models](../consistency-models/README.md) for stale-read reasoning.

## Further reading

- AWS, "Caching strategies" (cache-aside, write-through, TTL):
  https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/Strategies.html
- Redis, "Key eviction policies": https://redis.io/docs/latest/develop/reference/eviction/
- Redis, "Bloom filter" and "HyperLogLog": https://redis.io/docs/latest/develop/data-types/probabilistic/
- Facebook, "Scaling Memcache at Facebook" (stampede, leases), NSDI '13:
  https://www.usenix.org/system/files/conference/nsdi13/nsdi13-final170_update.pdf

## Cleanup

```bash
make reset
```
