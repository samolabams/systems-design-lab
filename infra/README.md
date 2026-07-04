# infra/ — the infrastructure catalog

This is **supporting lab documentation**, not a numbered systems-design module.
The study modules cover the concepts; this catalog explains where the concrete
configuration for those concepts lives.

Everything that is **not application code** lives here, one folder per role.
Each folder documents the configuration and role of that infrastructure
component. This map explains where each kind of infrastructure fits in the lab.

| Folder | Role (what it does) | Used in |
|---|---|---|
| [gateway/](gateway/) | The front door — load balancing and routing | load balancing, scaling |
| [database/](database/) | Durable state — Postgres (primary/replica) + PgBouncer pooling | replication and failover |
| [cache/](cache/) | Fast in-memory store — Redis | caching, rate limiting, partitioning and sharding |
| [queue/](queue/) | Async messaging — RabbitMQ | async queues (Kafka in event streaming) |
| [observability/](observability/) | Seeing the system — Prometheus + Grafana | observability |

## How a request flows through these

```
client ─▶ gateway ─▶ app ─▶ cache?  ─▶ database
                       └──▶ queue ─▶ worker ─▶ database
                                    (observability watches every hop)
```

The `app` itself is application code and lives in [../apps/](../apps/),
not here. Each folder above has its own README explaining the trade-off it
supports.
