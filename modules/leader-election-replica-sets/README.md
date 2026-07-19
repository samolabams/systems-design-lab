# Leader Election & Replica Sets

**Track:** Components
**Prerequisites:** [Databases](../databases/README.md), [Database scaling](../database-scaling/README.md)

## Outcome

After this module, you should understand leader election as the mechanism a
replicated system uses to keep one safe write leader under failure. You should be
able to explain:

1. Why replicated data systems usually need one write leader at a time.
2. How majority quorum prevents split-brain.
3. Why automatic election improves recovery time but can pause writes.
4. Why losing majority should make a node refuse writes.
5. How write concern and read preference expose consistency and availability
   trade-offs.
6. Why MongoDB is the lab implementation, not the only system that uses this
   pattern.

## What you will build or run

1. A local replica-set style cluster with one elected primary role.
2. Commands that show which node is primary and which nodes are followers.
3. A failure scenario that forces the group to choose a new leader.
4. A link between leader election, quorum, and safe writes.

## Why this matters

Replication gives a system extra copies of data, but copies create a safety
problem: if more than one copy accepts writes independently, the system can split
into conflicting histories. Leader election solves that problem by letting the
replica group agree on exactly one node that may accept writes.

[Replication and failover](../replication-failover/README.md) shows manual
failover: a standby exists, but an operator promotes it. This module shows the
automatic version. When the current leader disappears, the surviving nodes hold
an election. If a majority can communicate, one follower becomes the new leader.
If no majority exists, the remaining nodes stop accepting writes rather than risk
split-brain.

That behavior is a core design trade-off. Automatic election lowers recovery
time, but it does not make the system always writable. During detection and
election, writes can pause. During a partition, the minority side should become
unwritable. A design that uses automatic failover must explain those pauses and
the quorum rule behind them.

## Concept

- **Leader / primary** - the replica that accepts writes for the group.
- **Follower / secondary** - a replica that copies the leader's ordered write log
  and may serve reads, depending on the consistency requirements.
- **Replica set** - a group of nodes that store the same logical data and elect a
  leader from among themselves.
- **Election** - the process of choosing a new leader when the current leader is
  unreachable.
- **Majority quorum** - more than half the voting members. In a three-node group,
  two nodes form a majority. In a five-node group, three nodes form a majority.
- **Split-brain** - a failure mode where two isolated sides both believe they can
  accept writes. This creates histories that may conflict when the partition
  heals.
- **Write concern** - the rule for how many replicas must acknowledge a write
  before it is considered durable.
- **Read preference** - the rule for where reads are sent: the leader for fresher
  reads, or followers when lower latency or read scale matters more.

The key rule is simple:

```text
Only a node that can reach a majority is allowed to be leader.
```

For voting members, majority means `floor(N / 2) + 1`:

| Voting members | Majority required | What minority must do |
|---|---:|---|
| 1 | 1 | no failover possible |
| 3 | 2 | lone node steps down/refuses writes |
| 5 | 3 | one or two isolated nodes refuse writes |

Election is not instant. The group first has to detect that the old primary is
unreachable, wait out its election timeout, then vote for a replacement. During
that detection-and-election window, writes may fail or retry even though a new
primary will appear shortly.

That rule is what makes automatic election safe. If a network partition splits a
three-node group into a side with two nodes and a side with one node, only the
two-node side can elect or keep a leader. The one-node side must step down and
refuse writes. That is a CP choice in CAP terms: preserve one consistent history,
even if some clients temporarily lose write availability.

## How it works

The lab uses MongoDB because a three-node replica set gives a compact, runnable
implementation of election, quorum, and step-down behavior.

The Compose profile starts:

```text
mongo1 + mongo2 + mongo3 + mongo-init
```

The `mongo-init` one-shot runs
[`init-replica.sh`](../../infra/database/mongo/init-replica.sh). It waits for the
MongoDB nodes, calls `rs.initiate(...)`, and forms replica set `rs0` with three
voting members.

The demo then walks the safety story:

1. Inspect the topology and identify the current `PRIMARY`.
2. Write a document with majority durability.
3. Kill the primary.
4. Wait for the surviving majority to elect a new primary.
5. Read the document from the new primary.
6. Kill a second node and watch the lone survivor step down because it no longer
   has majority.
7. Restart the killed nodes and watch them rejoin as secondaries.

MongoDB names the roles `PRIMARY` and `SECONDARY`; other systems may say
`leader` and `follower`. The design idea is the same.

## Run

```bash
make leader-election-replica-sets
./modules/leader-election-replica-sets/demo.sh
```

Run non-interactively with:

```bash
AUTO=1 ./modules/leader-election-replica-sets/demo.sh
```


## How to read the commands

The demo uses MongoDB shell commands and Docker failure injection:

| Command shape | Meaning |
|---|---|
| `rs.status()` | show replica-set members and their current roles |
| `db.hello().primary` | ask which node is currently primary |
| `insertOne(..., { writeConcern: { w: "majority" } })` | write only after a majority acknowledges |
| `docker compose kill mongo1` | remove the current leader from the group |
| `docker compose kill mongo3` | remove another member and break majority |
| `docker compose up -d mongo1 mongo3` | heal the group so killed members rejoin |

Read these as generic distributed-systems events: inspect membership, write with
quorum, remove the leader, elect a replacement, then remove majority and reject
writes.

## How to read the output

One `PRIMARY` and two `SECONDARY` members means the group has exactly one write
leader. A new `PRIMARY` after the old one dies proves automatic election. A lone
survivor returning `false` for `ismaster` proves quorum safety: without a
majority, the node refuses to act as leader.

Expect a short gap between killing the old primary and seeing the new primary.
That gap is the election timeout and vote process made visible.

The document written before failover should still be readable after election.
That is the point of majority write concern: a write acknowledged by a majority
survives the loss of one node in a three-node group.

For each cluster state, write one sentence in this form:

```text
This election behavior proves _____ because the replica set reports _____.
```

## What to observe

1. **Single leader** - the topology starts with one `PRIMARY` and two
   `SECONDARY` nodes.
2. **Majority write** - the document is acknowledged by a quorum before the
   primary is killed.
3. **Automatic election** - after the primary dies, one surviving secondary
   becomes the new primary without manual promotion.
4. **Write pause** - election is not instant; the system needs time to detect
   failure and agree on a new leader.
5. **Quorum safety** - after a second node dies, the lone survivor steps down and
   refuses writes because one of three is not a majority.
6. **Recovery** - restarted nodes rejoin as secondaries and catch up from the
   write log.

## What you learned

- Leader election chooses one node to coordinate writes or decisions.
- A quorum prevents split-brain decisions when some nodes cannot communicate.
- Failover improves availability but may create brief periods of unavailability.
- Replica-set behavior is a concrete example of coordination under failure.

## Practice experiments

1. Predict what happens if two nodes fail in a three-node replica set.
2. Explain why three voting members tolerate one failure, while five tolerate two.
3. Compare automatic election here with the manual `pg_promote()` drill in
   [Replication and failover](../replication-failover/README.md).
4. Decide which user-facing operations should be blocked during election and
   which could safely continue as reads.

## Trade-offs

- **Faster recovery vs more coordination.** Automatic election removes manual
  promotion from the recovery path, but it needs failure detection, quorum, and
  election rules.
- **Consistency vs write availability.** A minority partition should refuse
  writes. That preserves one history, but some clients lose write availability
  until the partition heals.
- **Redundancy is not write scaling.** A leader-elected replica set still has one
  write leader. Extra nodes improve recovery and can help reads, but they do not
  make all nodes independent write targets.
- **Odd voting counts are easier.** Three or five voting members avoid ties and
  give a clear majority rule.
- **Read routing changes guarantees.** Reading from followers can reduce load or
  latency, but it can return stale data unless the system enforces stronger read
  guarantees.

## Next steps

- [Replication and failover](../replication-failover/README.md) for database failover behavior.
- [Consistency models](../consistency-models/README.md) for stale reads and quorum reasoning.
- [Availability](../availability/README.md) for the reliability impact of redundancy.

## Further reading

- MongoDB, "Replica Set Elections": https://www.mongodb.com/docs/manual/core/replica-set-elections/
- Ongaro & Ousterhout, "In Search of an Understandable Consensus Algorithm (Raft)":
  https://raft.github.io/raft.pdf
- Raft visualization: https://raft.github.io/
- Jepsen, "MongoDB" analyses: https://jepsen.io/analyses

## Cleanup

```bash
make reset
```
