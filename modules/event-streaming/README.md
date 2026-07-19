# Event Streaming And Replayable Logs

**Track:** Components
**Prerequisites:** [Async queues](../async-queues/README.md)

## Outcome

After this module, you should understand event streaming as a replayable log
model rather than a queue variant. You should be able to explain:

1. Why some systems need durable event history instead of delete-on-consume work
   queues.
2. What topics, partitions, offsets, producers, consumers, and consumer groups
   mean.
3. Why ordering is guaranteed within a partition, not across all partitions.
4. How keyed events choose a partition and preserve per-key order.
5. Why consumer offsets make replay possible.
6. How retention differs from acknowledgement-based deletion.
7. When to choose a queue like async queues versus an event log like event streaming.

## What you will build or run

1. A Kafka-backed event log with produced events and consumer reads.
2. A topic and consumer group flow that shows replay and offset tracking.
3. A contrast between event streams and work queues.
4. A scenario where multiple consumers can read the same history for different purposes.

## Why this matters

**Event streaming is the system design pattern of storing facts in an append-only
log so multiple consumers can process and replay them independently.** A queue is
usually about doing work once. A log is about keeping a durable history of what
happened.

Many systems need that history: analytics pipelines, audit trails, fraud
detection, data lake ingestion, event sourcing, notification fan-out, and CDC
pipelines. Different teams or services may need to read the same
events at different speeds. Some may need to restart from the beginning after a
bug or build a new derived view later.

The concept is independent of any one broker. The lab uses Kafka as one concrete
implementation so topics, partitions, offsets, consumer groups, retention, and
replay are visible. The core idea is the append-only, partitioned, replayable
event log. **Lag** is the distance between a consumer group's committed position
and the head of the log, measured in record offsets or elapsed time.

## Concept

An event log records events in order:

```text
producer -> topic partition -> ordered records with offsets -> consumers
```

A producer appends records. The log assigns each record an **offset**, which is
its position in a partition. Consumers read records and track their own offsets.
Reading does not delete the record.

Common event streaming terms:

- **Event** - a fact that something happened, such as `user1 logged in`.
- **Producer** - a component that writes events.
- **Topic** - a named stream of related events.
- **Partition** - one ordered slice of a topic.
- **Offset** - a record's position within a partition.
- **Consumer** - a process that reads events.
- **Consumer group** - a named set of consumers that share partitions for
  scale-out.
- **Retention** - how long records remain in the log, independent of whether they
  were consumed.
- **Replay** - reading old records again from an earlier offset.
- **Lag** - the distance between a consumer group's committed offset and the
   latest produced record, measured in offsets or elapsed time.

Partitions provide parallelism, but they also define the ordering boundary:

```text
same key -> same partition -> ordered for that key
different keys -> different partitions -> parallelism, no global order
```

A consumer group lets several consumers cooperate. Within one group, each
partition is assigned to one consumer at a time. Different groups each get their
own view of the log, so analytics and audit consumers can both read all events
without stealing work from each other.

Queue and log comparison:

| Mechanism | What happens after read? | Best for |
|---|---|---|
| Queue | message is acknowledged and removed | task distribution, do this once |
| Event log | record stays until retention removes it | replay, fan-out, event history |

## How it works

The general roles are represented by local lab components:

| General role | Lab implementation |
|---|---|
| event broker | Kafka |
| topic | `events` |
| partitions | three topic partitions |
| producer | Kafka console producer |
| consumer group | `analytics` |
| replaying consumer group | `audit` |
| observability | Kafka UI at `localhost:8081` |

The `event-streaming` profile starts a single Kafka broker in KRaft mode.
KRaft is Kafka's built-in metadata consensus mode and replaces the older
ZooKeeper dependency. The lab uses one broker because the goal is to observe the
log model, not broker replication.

The demo creates a topic with three partitions, produces keyed events, consumes
them with one consumer group, shows committed offsets, then consumes again with a
new group from the beginning. The replay proves that records are retained after
consumption.

The Kafka CLI commands use timeouts such as `--timeout-ms 6000` so the demo ends
after available records are consumed instead of waiting forever for future
events. In a real consumer service, the process usually stays alive and polls
continuously; the timeout is only for a finite lab script.

Kafka retention is the upper bound on replay. A consumer can replay only records
that still exist in the topic. Lag means a consumer group's committed offset is
behind the latest produced offset; if lag grows longer than retention allows, the
oldest unprocessed records can disappear before the consumer reads them.

When reading this module, keep these layers separate:

```text
topic          -> named event stream
partition      -> ordered shard of that stream
offset         -> position in one partition
consumer group -> independent reader progress
retention      -> how long records remain available
```

If streaming behavior is confusing, ask which topic is being read, which
partition holds the key, which group is reading, and what offset that group has
committed.

## Run

Run these commands from the repository root:

```bash
```

The output should end with:

```text
systems-design
```

Start the event streaming profile:

```bash
make event-streaming
```

Then run the guided demo:

```bash
./modules/event-streaming/demo.sh
```

Kafka UI is available at `http://localhost:8081`.

## How to read the commands

Creating a topic has this shape:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic events --partitions 3 --replication-factor 1
```

Read that as: create a stream named `events` with three ordered partitions.

Producing keyed events has this shape:

```bash
printf 'user1:login\nuser1:click\n' | \
  kafka-console-producer.sh --topic events \
  --property parse.key=true --property key.separator=:
```

Read that as: write events where the text before `:` is the key. Events with the
same key go to the same partition.

Consuming with a group has this shape:

```bash
kafka-console-consumer.sh --topic events --group analytics --from-beginning
```

Read that as: read records as part of the `analytics` consumer group, starting at
the beginning if the group has no committed offset yet.

Inspecting offsets has this shape:

```bash
kafka-consumer-groups.sh --describe --group analytics
```

Read that as: show how far the group has consumed in each partition and how much
lag remains.

## How to read the output

A topic description shows partitions:

```text
Topic: events  PartitionCount: 3
```

That means the topic has three independent ordered logs.

A consumed event may show its key and value:

```text
user1 login
user1 click
```

Events for `user1` stay in key order because they are routed to the same
partition. Events for different users can be processed in parallel and do not
have one global order.

A consumer-group description includes offsets and lag. Conceptually:

```text
CURRENT-OFFSET  LOG-END-OFFSET  LAG
6               6               0
```

Read that as: the group has consumed through the end of the partition. A positive
lag means new records exist that the group has not read yet.

If a new group can read the same events from the beginning, that proves the log
was not deleted by the first consumer group.

## What to observe

1. **A topic is partitioned** - the `events` topic has three partitions for
   parallelism.
2. **Keys control placement** - events with the same key go to the same
   partition, preserving per-key order.
3. **Consumer groups track progress** - the `analytics` group advances offsets as
   it reads.
4. **Reading is non-destructive** - the `audit` group can replay events after
   `analytics` already consumed them.
5. **Lag is stream backpressure** - if producers write faster than a group reads,
   group lag grows.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves the log is replayable because a new group can read from the beginning.
```

## What you learned

- Event streams keep an ordered, replayable log of facts that happened.
- Consumers track offsets so they can resume or replay work.
- Consumer groups coordinate which members process partitions.
- Streams are useful for history, integration, and derived views, but they add ordering and retention choices.

## Practice experiments

After the guided demo, make one change at a time and predict the effect before
running the command again:

1. **Produce more events for the same key.** Confirm they stay ordered for that
   key.
2. **Produce events for new keys.** Observe that different keys may spread across
   partitions.
3. **Use a new consumer group.** Read from the beginning again and explain why
   the old records still exist.
4. **Describe a derived-view consumer.** Explain how a new consumer group could
   rebuild analytics or audit state from the beginning of the log.
5. **Compare with async queues.** Explain why a queue is better for one-off jobs but a log
   is better for replayable history.

## Trade-offs

- **Logs enable replay but cost storage.** Retention must match audit, recovery,
  and replay needs.
- **Ordering is per partition.** A single ordered key can limit parallelism if all
  traffic goes to one partition.
- **Consumer groups add operational state.** Offsets, lag, rebalances, and
  retention windows need monitoring.
- **Streams are not job queues by default.** Use a queue when work should be
  claimed and deleted after completion.
- **Event schemas become contracts.** Once many consumers depend on an event,
  changing its shape requires compatibility discipline.

## Next steps

- [Message delivery semantics](../message-delivery-semantics/README.md) for duplicates and idempotency.
- [Sagas](../sagas/README.md) for event-driven workflows.
- [Observability](../observability/README.md) for watching event pipelines.

## Further reading

- Kafka, "Introduction" (logs, partitions, consumer groups):
  https://kafka.apache.org/documentation/#introduction
- Jay Kreps, "The Log: What every software engineer should know about real-time
  data's unifying abstraction":
  https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying
- Kafka, "Design": https://kafka.apache.org/documentation/#design

## Cleanup

```bash
make reset
```
