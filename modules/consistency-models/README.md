# CAP / PACELC & consistency models

**Track:** Foundations
**Prerequisites:** [Replication and failover](../replication-failover/README.md), [Leader election and replica sets](../leader-election-replica-sets/README.md)

## Outcome

After this module, you should be able to name common consistency
models, connect each one to a read/write behavior, and explain how CAP and PACELC
describe the trade-offs made during partitions and normal operation.

## What you will build or run

1. A consistency vocabulary map for reads, writes, replicas, lag, and quorum.
2. Timeline examples that distinguish strong consistency from eventual consistency.
3. A read-after-write scenario that explains why users may see stale data.
4. A CAP/PACELC decision table for availability, latency, and consistency trade-offs.

## Why this matters

"Consistency" is the single most overloaded word in systems design. Most
production incidents that look like bugs ("the write succeeded, but the data is not there") are
really a *consistency model* doing exactly what it promised. Naming the models
precisely allows the model to be chosen deliberately instead of discovered during an
outage. This module ties each model to the exact lab step that proves it.

## Concept

A consistency model is the contract a datastore offers about *what a read can
see*. The ones the lab demonstrates, strongest to weakest:

| Model | What it guarantees | Proven by |
|---|---|---|
| **Strong / linearizable** | every read sees the most recent write, as if there were one single copy of the data | replication and failover read from the **primary** |
| **Eventual** | copies (replicas) may lag but will agree *eventually* once updates propagate | Replication and failover **lag** on the replica |
| **Read-your-writes** | after a client writes, that same client sees the write on its next read | replication and failover read-after-write **404** (when violated) |
| **Monotonic reads** | reads never go backwards in time; a client does not see data disappear and then reappear | pin a session to one replica (load balancing `ip_hash`) |
| **Causal** | if A caused B, everyone sees A before B | ordering via a log (event streaming, single partition) |

Full notes: [consistency.md](consistency.md).

## How it works

Two theorems frame the choice:

- **CAP describes partition-time behavior.** A *network partition* happens when
  nodes can no longer talk to each other: a broken link splits the cluster into
  groups that cannot sync. While that lasts, the system must choose. Pick
  **C**onsistency and the system refuses to serve data that might be stale or
  conflicting; pick **A**vailability and the system keeps serving, accepting that
  the two sides may drift apart. leader election's Mongo election takes the first
  path (**CP**): the minority side stops accepting writes so the two sides never
  diverge into conflicting histories that cannot be merged.
- **PACELC describes partition-time and normal-operation behavior.** It extends
  CAP with the common case: *if Partition then C-or-A, Else choose Latency or
  Consistency*. replication and failover's async replica is an **EL** choice: it
  trades freshness for read latency and scale when the network is healthy.

The lab makes the abstract concrete: the read-after-write 404 in replication and failover *is*
eventual consistency; the rejected write in leader election *is* a CP partition choice.

## Run

```bash
pwd
make replication-failover   # eventual + read-your-writes hazard (live)
./modules/replication-failover/demo.sh
make leader-election-replica-sets   # CP under partition (automatic election)
./modules/leader-election-replica-sets/demo.sh
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

The replication and failover commands show consistency during normal operation with asynchronous
replication. The leader election commands show behavior during a partition or node failure.
Read them as two different questions: what can a read see, and what should a
cluster do when not all nodes can agree?

## How to read the output

A successful primary read after a write demonstrates strong behavior on that
path. A temporary miss on the replica demonstrates eventual consistency and a
read-your-writes violation. An election or rejected write during partition shows
a CP choice: preserve a single history even if some clients cannot write.

## What to observe

1. A read from the **primary** always reflects the latest write — *strong*.
2. The same read from the **async replica** (an *asynchronous* copy that applies
   changes a moment after the primary, rather than in lock-step) can miss a
   just-written row until the WAL — the write-ahead log the primary streams to
   its replicas (replication and failover) — catches up. That is *eventual* consistency, and the
   read-your-writes hazard, in action.
3. Pinning a client to one replica removes the "time going backwards" flicker —
   *monotonic reads* — at the cost of balance (load balancing `ip_hash`).

## What you learned

- Consistency describes what a read is allowed to return after writes happen.
- Replication and asynchronous workflows often create stale-read windows.
- Strong consistency, eventual consistency, and read-your-writes behavior serve different needs.
- CAP and PACELC are tools for explaining trade-offs, not slogans to memorize.

## Practice experiments

1. Explain which user actions require read-your-writes behavior.
2. Identify a feature where eventual consistency is acceptable.
3. Map one observed replication and failover behavior to PACELC's latency-versus-consistency choice.

## Trade-offs

- Strong consistency is simplest to reason about, but across replicas it requires
  coordination before a write or read can be considered current. Synchronous
  replication can block a write until the required replicas acknowledge it, which
  adds latency tied to replica round trips. During a partition, the system may reject
  some reads or writes rather than risk serving conflicting data; default to it
  until the numbers (estimation) force a weaker model for scale.
- Eventual consistency scales reads cheaply but makes correctness the
  *application's* job (application code must handle the "it is not there yet" case, e.g.
  by retrying or reading from the primary).
- Most real systems are a *mix*: strong for the write path, eventual for
  **fan-out reads** (a single request that reads from many replicas in parallel
  to spread the load).

## Next steps

- [Replication and failover](../replication-failover/README.md) for a runnable stale-read example.
- [Leader election and replica sets](../leader-election-replica-sets/README.md) for primary selection.
- [Partitioning and sharding](../partitioning-sharding/README.md) for consistency across data slices.

## Further reading

- Gilbert & Lynch, the CAP theorem proof (2002):
  https://www.comp.nus.edu.sg/~gilbert/pubs/BrewersConjecture-SigAct.pdf
- Daniel Abadi, "Consistency Tradeoffs in Modern Distributed Database Design"
  (PACELC): https://www.cs.umd.edu/~abadi/papers/abadi-pacelc.pdf
- Jepsen, "Consistency Models" (an interactive map): https://jepsen.io/consistency
- *Designing Data-Intensive Applications*, Ch. 5 & 9.

## Cleanup

```bash
make reset
```
