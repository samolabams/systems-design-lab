# Estimation Worksheet (Modern, 2026 Numbers)

Fill in the blanks for the system you are designing. The point is an *order of
magnitude*, not precision.

## Latency numbers worth memorizing (modern)

| Operation | Rough time |
|---|---|
| L1 cache reference | ~1 ns |
| Main memory reference | ~100 ns |
| Redis GET (same DC) | ~0.1–0.5 ms |
| SSD random read | ~50–150 µs |
| Relational database indexed point read | ~0.2–1 ms |
| Intra-DC network round trip | ~0.5 ms |
| Cross-region round trip (US↔EU) | ~80–150 ms |
| Kafka produce (acked) | ~1–5 ms |

## Powers of two

| Power | Exact | Approx | Name |
|---|---|---|---|
| 10 | 1,024 | 1 thousand | KB |
| 20 | 1,048,576 | 1 million | MB |
| 30 | ~1.07e9 | 1 billion | GB |
| 40 | ~1.10e12 | 1 trillion | TB |

## Capacity template

```
Daily active users (DAU):          __________
Actions / user / day:              __________
Read : Write ratio:                __________ : 1

Writes/day  = DAU * actions * write_fraction = __________
Writes/sec  = writes/day / 86,400            = __________
Peak QPS    = avg QPS * 2..10 (peak factor)  = __________

Avg record size:                   __________ bytes
Storage/day = writes/day * size              = __________
Storage/5yr = storage/day * 365 * 5          = __________

Bandwidth   = peak QPS * payload size        = __________
```

## Sanity checks (do you actually need machinery?)

- Writes/sec well under ~10k and storage under ~10 TB? A single tuned relational database
  (+ read replica, replication and failover) likely suffices — do **not** shard yet (when not to scale).
- Read-heavy with a hot set? A cache (caching) before a shard (partitioning and sharding).
- 1M+ msgs/s of events? Now a log (Kafka, event streaming) earns its place.
