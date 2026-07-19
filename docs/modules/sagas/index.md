# Distributed Transactions & Sagas

**Track:** Components
**Study role:** Advanced — microservices transaction design after queues, logs, and idempotency are understood.
**Prerequisites:** [Async queues](/modules/async-queues/), [Event streaming](/modules/event-streaming/), [Message delivery semantics](/modules/message-delivery-semantics/)

## Outcome

After this module, you should understand sagas as the standard way
to coordinate multi-step business workflows without a global database
transaction. You should be able to explain:

1. Why distributed transactions are different from one local ACID transaction.
2. Why two-phase commit is often avoided in service-oriented systems.
3. How a saga uses a sequence of local transactions.
4. What compensating actions mean and why they are semantic undo operations.
5. How orchestration differs from choreography.
6. Why saga steps and compensations need idempotency.

## What you will build or run

1. A three-step order workflow with inventory, payment, and shipment transactions.
2. A scenario where inventory and payment succeed but shipment fails.
3. A compensation path that refunds payment and releases inventory without a distributed transaction.
4. A comparison table for orchestration and choreography.

## Why this matters

A single business action often spans several services — *shorten + bill + notify* —
each with its own database. There is no cross-service `BEGIN…COMMIT`, and the
classic **two-phase commit (2PC)** is fragile (it blocks on the coordinator and
does not scale). The **saga** pattern is how real systems keep multi-service writes
consistent without a global transaction.

## Concept

- **Compensating action** — application logic that semantically undoes a prior
  committed step, such as refunding a payment or releasing reserved inventory. It
  is not a transaction rollback; it is a new business action that restores the
  intended outcome.
- **Why not 2PC** — a *blocking* coordinator (every participant waits, holding its
  resources, until the coordinator says commit-or-abort), locks held across the
  network, and a single point of failure; it trades availability for an atomicity
  guarantee that many workflows do not require.
- **Saga** — a sequence of local transactions, each publishing an event that
  triggers the next. If a step fails, run compensating actions for the prior
  committed steps.
- **Orchestration vs choreography** — a central orchestrator drives the steps, or
  services react to each other's events (choreography). Trade central clarity for
  decoupling.
- **Idempotent retries** — every step must tolerate redelivery (ties to message delivery semantics);
  retries are how a saga makes forward progress.
- **Dual-write problem** — updating a DB and publishing an event are two writes
  that can diverge; the transactional outbox fixes it.

The usual idempotency guard is a local transaction: insert a unique step key,
perform the step only if that insert succeeds, and commit both together. If the
same step is delivered again, the key already exists, so the handler skips the
side effect.

## How it works

The demo models a *place-order* saga across three "services", each a separate
Postgres table with its own local transaction: **reserve inventory → charge
payment → create shipment**. A bash orchestrator (`demo.sh`) advances step by
step. There is no global transaction — each step commits on its own.

- **Happy path** (`order-1`): the successful case where all three local
  transactions commit in order.
- **Partial failure** (`order-2`): it ships to a `restricted` region with no
  carrier, so step 3 fails. The orchestrator then runs **compensations** for the
  steps that already committed, in reverse — refund the payment, return the
  reserved stock — leaving the system consistent again.
- **Idempotent retry**: every step claims an idempotency key (`saga_processed`)
  before doing work, so a redelivered step is a no-op instead of double-applying.

The transport is deliberately omitted — in production each step's event would
travel over RabbitMQ (async queues) or Kafka (event streaming), and the
transactional outbox from [message delivery semantics](/modules/message-delivery-semantics/)
would keep the DB write and its event from diverging. Here the steps are called directly so
the saga's *control flow* (advance vs. compensate) is the only moving part.

## Run

```bash
make sagas
./modules/sagas/demo.sh
```

Run non-interactively with `AUTO=1 ./modules/sagas/demo.sh`.


## How to read the commands

The demo is an orchestrated saga expressed as shell functions and SQL. Each saga
step performs one local transaction against one service-owned table:

```text
reserve inventory -> charge payment -> create shipment
```

The failure path compensates completed steps in reverse order:

```text
refund payment -> release inventory
```

Read the SQL tables as service boundaries for the lab. In production these would
usually be separate services and databases, connected by events or commands.

## How to read the output

For the happy path, look for one `done` row per step. For the failed order, look
for completed reserve and charge steps followed by `compensated` rows. The key
idea is that the system is made consistent by forward actions and semantic undo,
not by rolling back one global transaction.

When the reserve step is retried and stock does not change, the idempotency key
has prevented duplicate application of a redelivered command.

For each saga step, write one sentence in this form:

```text
This workflow remains consistent because the step reached _____ and the recovery action is _____.
```

## What to observe

1. The happy path: each local transaction commits and the order completes
   (stock 5 → 4, one payment, one shipment).
2. A failure at step 3 triggers compensations for steps 1–2 — the payment is
   refunded and the 2 reserved units return to stock (back to 4).
3. A redelivered `reserve` for `order-1` is skipped by the idempotency key; the
   stock count does not move.
4. The `saga_log` shows every step's outcome, including the two
   `compensated` rows for the failed order.

## What you learned

- Sagas coordinate multi-step workflows when one database transaction cannot cover every service.
- Compensating actions are business actions, not automatic rollbacks.
- Orchestration centralizes workflow control; choreography distributes it through events.
- Sagas require clear state, retries, idempotency, and failure handling.

## Practice experiments

1. Change the failing region and predict whether compensation will run.
2. Add a new saga step on paper and define its compensation.
3. Decide which steps are not truly undoable, such as email or shipping handoff.
4. Explain where the transactional outbox would be used if each step published an event.

## Trade-offs

- **No isolation** — other transactions can see intermediate saga state; design
  around it with states such as "pending," unlike an ACID transaction.
- **Compensation is difficult** — some actions cannot be cleanly undone, such as
  a sent email; compensation must be semantic, such as sending a correction.
- **Orchestration coupling vs choreography sprawl** — central orchestrators become
  bottlenecks/God-services; pure choreography becomes hard to follow.
- **More failure modes** — every step and compensation can itself fail and retry.

## Next steps

- [Message delivery semantics](/modules/message-delivery-semantics/) for retries and idempotency.
- [Event streaming](/modules/event-streaming/) for choreography foundations.
- [Async queues](/modules/async-queues/) for background step execution.

## Further reading

- Hector Garcia-Molina & Kenneth Salem, "Sagas" (1987):
  https://www.cs.cornell.edu/andru/cs711/2002fa/reading/sagas.pdf
- microservices.io, "Saga pattern":
  https://microservices.io/patterns/data/saga.html
- Chris Richardson, *Microservices Patterns*, ch. 4–5.
- AWS, "Saga orchestration with Step Functions":
  https://docs.aws.amazon.com/step-functions/latest/dg/sample-saga-pattern.html

## Cleanup

```bash
make reset
```
