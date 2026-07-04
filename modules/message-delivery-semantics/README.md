# Message delivery semantics, outbox & idempotency

**Track:** Components
**Study role:** Advanced — study after replication, queues, and event streaming are understood.
**Prerequisites:** [Event streaming](../event-streaming/README.md)

> **Status:** Runnable - demonstrates outbox, deduplication, and effectively-once processing with the base database and event broker.

## Outcome

After this module, you should understand message delivery semantics
and why reliable distributed workflows are usually designed around at-least-once
delivery plus idempotent processing. You should be able to explain:

1. The difference between at-most-once, at-least-once, exactly-once delivery, and
  effectively-once processing.
2. Why brokers commonly choose at-least-once delivery instead of silently losing
  messages.
3. Why updating a database and publishing an event as separate writes creates the
  dual-write problem.
4. How a transactional outbox makes the business write and event record commit in
  one local transaction.
5. How consumer-side deduplication and idempotency make duplicate deliveries
  harmless.
6. Why effectively-once processing is a practical design claim, not the same
  claim as exactly-once delivery.

## What you will build or run

1. A message-processing scenario with retries and duplicate delivery risk.
2. A consumer group run that shows how messages are claimed and processed.
3. An idempotency or deduplication path that makes repeated delivery safe.
4. An outbox-style reasoning model for connecting database writes to message publication.

## Why this matters

Distributed systems communicate across unreliable boundaries: networks time out,
brokers retry, consumers crash, and acknowledgements can be lost. The first
design question is therefore not "which broker do we use?" It is: **what delivery
semantics can the system honestly provide, and what must the application do when
a message is delivered more than once?**

Most production messaging designs prefer duplicate messages over lost messages.
That leads to at-least-once delivery, which is useful only when consumers are
idempotent. This module teaches the delivery semantics first, then shows the
standard application pattern: transactional outbox on the producer side and
deduplication on the consumer side.

## Concept

Message delivery semantics describe what a messaging system promises when
publish, consume, acknowledgement, retry, and crash behavior interact.

| Semantics | Promise | Common failure mode | Application requirement |
|---|---|---|---|
| **At-most-once delivery** | A message is delivered zero or one time. | A crash or timeout can lose the message. | Use only when loss is acceptable. |
| **At-least-once delivery** | A message is delivered one or more times. | Retries can create duplicates. | Make consumers idempotent. |
| **Exactly-once delivery** | A message is delivered once and only once. | Usually not a realistic end-to-end broker claim across databases, services, and side effects. | Treat vendor claims carefully; ask what boundary the guarantee covers. |
| **Effectively-once processing** | The message may be delivered more than once, but the business effect happens once. | Requires durable deduplication state. | Store an idempotency key before applying the side effect. |

The practical default is **at-least-once delivery plus idempotent processing**.
The broker and relay retry when acknowledgements are uncertain, so the system
does not silently lose work. The consumer records enough state to recognize a
duplicate and skip the side effect.

That still leaves the producer-side problem. Suppose a service must create an
order in its database and publish `OrderCreated` to a broker. If those are two
independent writes, a crash can land between them: the order commits but the
event is missing, or the event is published for an order that later rolls back.
That is the **dual-write problem**.

The standard solution is the **transactional outbox**:

1. Write the business row and the "to-publish" event row in one local database
   transaction.
2. Let a relay publish committed outbox rows to the broker after the database
   commit.
3. Make consumers idempotent by recording processed event IDs before applying
   side effects.

Together, the outbox and idempotent consumer turn at-least-once delivery into
effectively-once processing for the business operation.

Consensus, quorum, and leader election are separate coordination concepts. They
are covered by [leader election and replica sets](../leader-election-replica-sets/README.md)
and [consistency models](../consistency-models/README.md).

## How it works

The concept is independent of any one database or broker. The lab uses the base
Postgres database and the Kafka broker from event streaming as one concrete
implementation of the reliability pattern around at-least-once messaging:

- **Outbox** — each order writes its business row *and* its "to-publish" event in
  **one local transaction**, so there is no window where the row committed but the
  event was lost (the dual-write bug). A relay then publishes unpublished outbox
  rows to Kafka and marks them published.
- **Consumer-side dedup** — every consumed event's id is inserted into a
  `processed` table with `ON CONFLICT DO NOTHING`; only a genuinely new event
  fires its side effect (a confirmation notification). A redelivery is a no-op.

The demo runs entirely through `psql` and the Kafka CLI (`compose exec`) - no new
service to read. The important point is not Kafka syntax; it is the boundary
between delivery and processing.

## Run

```bash
pwd
make message-delivery-semantics
./modules/message-delivery-semantics/demo.sh
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

The demo uses two command families:

| Command family | Meaning |
|---|---|
| `psql` statements | create tables, commit local transactions, inspect dedup state |
| Kafka CLI commands | create the topic, publish events, replay the log with a new group |

The important database operation has this shape:

```sql
BEGIN;
INSERT INTO orders ...;
INSERT INTO outbox ...;
COMMIT;
```

Read that as: the business row and the event-to-publish row are one atomic local
transaction. The Kafka publish happens later, through the relay. The relay may
publish or retry more than once, so the consumer must still deduplicate.

## How to read the output

Lines such as `orders=3 unpublished outbox=3` prove the local transaction
created business rows and outbox rows together. Lines such as `unpublished outbox
now=0` prove the relay published the pending rows and marked them complete.

During replay, output like `duplicate: skipped` proves the consumer-side dedup
table absorbed a redelivered event. If the notification count stays at three
after a second delivery, the side effect happened once per event even though the
broker delivered the events more than once. That is effectively-once processing
on top of at-least-once delivery.

## What to observe

1. The delivery guarantee is not the same as the processing guarantee.
2. The order row and its outbox event commit **together** - abort the transaction
  and neither exists.
3. The relay publishes committed outbox rows after the database commit.
4. First delivery processes all three events, producing three notifications.
5. **Replaying** the log under a new consumer group redelivers every event, but
  dedup absorbs them - notifications stay at three. Delivered twice, processed once.

## What you learned

- Delivery semantics describe what can happen when messages are sent, retried, or redelivered.
- At-least-once delivery requires idempotent consumers because duplicates are possible.
- Exactly-once behavior usually requires careful boundaries, not just a broker setting.
- Outbox and deduplication patterns connect durable state with message processing.

## Practice experiments

1. Add a fourth order and outbox row in the same transaction, then confirm the
  relay publishes it.
2. Replay the topic with another new consumer group and confirm notifications do
  not increase.
3. Classify the demo as at-most-once, at-least-once, exactly-once delivery, or
  effectively-once processing, and justify the answer.
4. Explain what would break if the order insert committed but the outbox insert
  did not.
5. Sketch which column would be the idempotency key in a payment or email system.

## Trade-offs

- **Delivery vs processing** — the broker may deliver a message more than once;
  idempotency keeps the side effect from happening more than once.
- **Dedup state** — idempotency keys/dedup tables must be stored and expired;
  they're a real dataset with its own scaling concerns.
- **Outbox adds a relay** — one more moving part, but it is the standard fix for
  dual writes.
- **Relay lag** — events are published after the database commit, so downstream
  consumers can observe a delay between the row commit and the event appearing.

## Next steps

- [Asynchronous queues](../async-queues/README.md) for basic background work.
- [Event streaming](../event-streaming/README.md) for replayable logs.
- [Sagas](../sagas/README.md) for multi-step distributed workflows.

## Further reading

- microservices.io, "Transactional outbox":
  https://microservices.io/patterns/data/transactional-outbox.html
- microservices.io, "Idempotent consumer":
  https://microservices.io/patterns/communication-style/idempotent-consumer.html
- Kleppmann, *Designing Data-Intensive Applications*, ch. 11 (stream processing).

## Cleanup

```bash
make reset
```
