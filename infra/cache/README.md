# infra/cache — fast in-memory store (Redis)

A cache sits between the app and the database to serve hot data in microseconds
instead of re-querying Postgres every time. The same Redis engine also backs
rate-limiting counters and shard-routing demos.

## What's here

Nothing yet — Redis currently runs on its image defaults (see the `redis`
service in [../../docker-compose.yml](../../docker-compose.yml)). When a lesson
needs custom config (e.g. `redis.conf`, eviction policy, cluster setup), it
lands in this folder.

## The lesson

Caching trades **freshness for speed**: the design must specify *when* to invalidate.
The hard problems are cache invalidation and the thundering-herd on a cold miss.

**Used in:** caching (caching), rate limiting (rate limiting), partitioning and sharding (sharding).
