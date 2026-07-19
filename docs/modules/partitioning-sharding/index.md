# Partitioning & Sharding

**Track:** Components
**Prerequisites:** [Databases](/modules/databases/), [Database scaling](/modules/database-scaling/)

## Outcome

After this module, you should understand partitioning and sharding as deliberate responses to write, storage, or key-distribution limits. You should be able to explain:

1. The difference between partitioning data and placing partitions on different nodes.
2. Why naive modulo moves too many keys when node count changes.
3. How consistent hashing reduces key movement during rebalancing.
4. Why virtual nodes smooth load and failure recovery.
5. Why sharding makes queries, transactions, and operations harder.

## What you will build or run

1. A sharding demonstration that maps keys to data partitions.
2. Commands that show which shard owns which key.
3. An uneven-distribution scenario for reasoning about balance.
4. A comparison between partitioning for manageability and sharding for scale.

## Why this matters

Eventually one node cannot hold all data or serve all write/storage traffic, so
the dataset is **partitioned**: split into smaller pieces. When those pieces live
on different nodes, the design is usually called **sharding**. Splitting is
straightforward; the hard part is what happens when **N changes** because a node
is added for growth or removed after failure. A poor sharding scheme reshuffles
almost every key on that change. For a cache, this causes a mass cache-miss
event; for a database, it requires copying most of the data while the system is
live. The goal is a scheme where adding or removing a node moves only its fair
share, approximately `1/N` of the keys.

This is not only a storage problem. The shard key becomes part of the product's
query model. If users frequently ask for all data for one customer, customer id
may be a good key. If they frequently ask for global leaderboards, customer id
may scatter the query across every shard. A good shard key spreads writes while
keeping the common reads as local as possible.

## Concept

- **Naive modulo** — `node = hash(key) % N`. Even distribution, but the node
  depends on `N`. Change `N` and the divisor changes, so nearly every key maps
  somewhere new.
- **Consistent hashing** — place both nodes and keys on a hash **ring** (a circle
  of, say, 0..2³²). A key is owned by the **next node clockwise**. Adding a node
  only captures the arc between it and its predecessor, so only the keys in that
  arc move — roughly `K/N`.
- **Virtual nodes** — multiple hash-ring positions assigned to one physical
  node. Placing each physical node at many positions (for example, 150) smooths
  uneven ownership ranges and reduces rebalancing spikes. It also reduces
  cascading failure risk: when one physical node fails, its key ranges spread
  across many successors instead of overloading one neighboring node.
- **Replication** — real systems also put each key on the next R nodes clockwise
  for redundancy; consistent hashing makes that placement natural.

Both schemes in language-neutral pseudocode — no JavaScript required:

```text
# Naive modulo
owner(key) = nodes[ hash(key) % len(nodes) ]

# Consistent-hash ring
build ring:
    for each node, for v in 0..vnodes:        # e.g. 150 virtual points per node
        ring[hash(node, v)] = node            # placed around a circle 0..2^32
    sort ring positions

owner(key):
    h = hash(key)
    return first node clockwise from h on the ring   # wrap past the end
```

## How it works

The demo's engine is a small script (`shard.js`) that implements exactly the
pseudocode above. It hashes 10,000 keys across 4 nodes two ways — modulo and a
consistent-hash ring with 150 vnodes per node — then adds a 5th node and
**counts how many keys changed owner** under each scheme. The lesson does not
require reading or modifying the implementation. `demo.sh` executes it in a
temporary hardened Node container; the important output is the two
key-movement numbers, not the source code.

Read the lab as a topology-change experiment. The keys are the same before and
after. The only thing that changes is the number of nodes. That isolates the
question this module cares about: how much data must move when the cluster grows
or shrinks?

> The **pseudocode above is the reference algorithm**. `shard.js` is one
> illustrative implementation used to execute the comparison.

## Run

```bash
make partitioning-sharding
./modules/partitioning-sharding/demo.sh
```


## How to read the commands

The demo runs a deterministic comparison script. Read it as two placement
functions receiving the same keys and node changes: modulo placement and
consistent-hash placement.

## How to read the output

Distribution counts show balance before a topology change. Key-movement counts
show rebalancing cost after adding a node. If modulo moves most keys and the ring
moves about one node's share, consistent hashing has reduced operational churn.

There are two separate signals. Balance tells whether load is spread *now*.
Movement tells how disruptive the next change will be. A scheme can look balanced
at steady state and still be expensive to operate if every resize moves almost
all keys.

## What to observe

1. **Both spread evenly at 4 nodes** — the distribution counts are all near
   `10000 / 4 = 2500`.
2. **Modulo reshuffles almost everything** — adding the 5th node moves on the
   order of **80%** of keys.
3. **The ring moves ~1/N** — adding the 5th node moves close to the ideal
   `10000 / 5 = 2000` keys (~20%), i.e. roughly one node's worth.
4. The gap between those two numbers is the whole point of consistent hashing.

For each placement scheme, write one sentence in this form:

```text
This scheme is easier/harder to operate because adding one node moved _____ keys.
```

## What you learned

- Partitioning splits data into pieces; sharding places those pieces across machines.
- The shard key controls distribution, query shape, and hot-spot risk.
- Cross-shard queries and transactions are more expensive than single-shard operations.
- Resharding is operationally hard, so key choice matters early.

## Practice experiments

1. Change the number of virtual nodes in `shard.js` and predict the balance
  effect.
2. Explain why a hot key is still hot even with perfect key distribution.
3. Sketch how adding replication would place each key on more than one node.

## Trade-offs

- **More vnodes = smoother but heavier** — more ring entries mean better balance
  and finer rebalancing, but more memory and a bigger structure to maintain.
- **Hot keys still matter** — sharding spreads *keys*, not *load per key*. A
  single heavily accessed key lands on one node regardless; replication or
  key-splitting is required for hot spots.
- **Multi-key operations become difficult** — joins and transactions across
  shards are expensive or impossible; access patterns must be designed around the shard key.
- **Rebalancing is still I/O** — consistent hashing minimises *how many* keys move,
  but those keys still have to be copied/re-warmed; plan for it.

## Next steps

- [Database scaling](/modules/database-scaling/) for deciding when sharding is needed.
- [Databases](/modules/databases/) for source-of-truth responsibilities.
- [Consistency models](/modules/consistency-models/) for distributed data trade-offs.

## Further reading

- Karger et al., "Consistent Hashing and Random Trees" (the original paper):
  https://www.cs.princeton.edu/courses/archive/fall09/cos518/papers/chash.pdf
- Amazon, "Dynamo: Amazon's Highly Available Key-value Store":
  https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf
- "A Guide to Consistent Hashing" (Toptal):
  https://www.toptal.com/big-data/consistent-hashing

## Cleanup

```bash
make reset
```
