# Consistency models → exact demo step

Each model below is tied to the precise lab step that makes it observable. This
is the difference between *naming* a model and *seeing* it.

## Strong / linearizable
- **Where:** read from `postgres-primary` (replication and failover step "write on primary, read on
  primary"). Every read reflects the latest committed write.
- **Cost:** all reads hit one node — no read scaling.

## Eventual consistency
- **Where:** replication and failover step "inspect replication lag". The replica trails the primary
  by `lag_bytes`; given no new writes it converges.
- **Cost:** a read on the replica may be stale.

## Read-your-writes
- **Where:** replication and failover step "read-after-write hazard" — write a
  shortened URL and then immediately read from the replica; a non-zero lag yields
  a `404`.
- **Fix:** route the user's own reads to the primary for a short window, or pin
  the session to the node it wrote to.

## Monotonic reads
- **Where:** pin a client to one replica (load balancing `ip_hash`). Without pinning, two
  reads can hit replicas at different lag and appear to go *backwards* in time.

## Causal consistency
- **Where:** an append-only log preserves order (event streaming, single partition).
  Effects never appear before their cause when consumers read the log in order.

## CP vs AP under partition
- **Where:** leader election. Kill the primary: the majority side elects a new
  primary and stays writable (CP); the minority side refuses writes rather than
  diverge.
