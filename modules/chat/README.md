# Design A Chat System

**Track:** Capstones

## Before you start

Complete or skim these modules first: [The design method](../design-method/README.md),
[Estimation](../estimation/README.md), [API gateway](../api-gateway/README.md),
[Async queues](../async-queues/README.md), [Event streaming](../event-streaming/README.md),
[Message delivery semantics](../message-delivery-semantics/README.md), and
[Observability](../observability/README.md). They provide the vocabulary this
capstone expects.

## Outcome

After this capstone, you should be able to design a chat system
around persistent connections, message ordering, delivery guarantees, presence,
fan-out, storage, retries, deduplication, and observability. You should be able
to trace a message from sender to durable storage to every connected or offline
recipient, including what happens when the sender retries.

## What you will build or run

1. A design artifact for a chat system, including message flow and storage responsibilities.
2. A decision about real-time delivery, offline delivery, and message history.
3. A plan for presence, fanout, ordering, and retry behavior.
4. A trade-off summary that connects chat requirements to infrastructure choices.

## Why this matters

Chat ties together almost everything: persistent connections, message ordering,
delivery guarantees, presence, and fan-out. It is the capstone that exercises
realtime transport (**WebSockets** — a long-lived two-way connection between
browser and server, unlike request/response HTTP), queues (async queues), and at-least-once
delivery with dedup (message delivery semantics) at the same time — a true integration test of the
guide.

The user expectation is deceptively strict: messages should feel instant, appear
once, remain readable later, and preserve room order. Those guarantees come from
different parts of the system. WebSockets make delivery feel realtime; durable
storage preserves history; sequence numbers or partitions preserve order; ids and
acknowledgements make retries safe.

## Concept

Apply the [design method](../design-method/README.md):

- **Transport** — persistent **WebSocket** connections (kept open so either side
  can push a message at any time) carried through the gateway; sockets are
  stateful and *pinned to a node* (a given client's socket lives on one specific
  server, so messages for it must be routed there).
- **Delivery semantics** — at-least-once delivery plus **dedup**
  (de-duplication) on a message id so a retry does not show the message twice.
- **Ordering** — messages within a conversation must appear in order; use per-room
  sequence numbers (a counter per chat room) or partitioned streams that key by
  room (event streaming-style keying, so one room's messages stay in one ordered partition).
- **Presence** — who's online and "typing…", tracked in a fast store (Redis) and
  fanned out to participants.
- **Delivery receipts** — sent / delivered / read state per message.
- **Fan-out & queues** — route a message to all participants' connections, possibly
  across nodes, via [async queues](../async-queues/README.md) / pub-sub.

## How it works

This capstone is a realtime correctness exercise. The design document should
separate connection management, message persistence, ordering, delivery retries,
presence, fan-out, and observability, then explain how a client reconnects
without losing or duplicating messages.

## Task

Apply the [design method](../design-method/README.md) end-to-end and write
a short design document. There is no required runnable demo. For optional
prototyping, start the referenced module profiles and connect clients over
WebSockets through the gateway. A strong answer:

1. Keeps messages in order within a room, even across reconnects.
2. Dedups a redelivered message so each shows exactly once.
3. Fans out presence updates ("online", "typing") to participants.
4. Survives a killed node — clients reconnect with no lost messages.

Use this design-document outline:

| Section | What to include |
|---|---|
| Requirements | one-to-one chat, group chat, online/offline behavior, ordering scope, delivery receipts, latency targets |
| Estimates | concurrent connections, messages/sec, room size distribution, storage growth, fan-out cost |
| API contract | connect, send message, receive message, ack/read receipt, reconnect/resume, fetch history |
| Data model | room, participant, message, sequence number, delivery receipt, presence state |
| Message flow | WebSocket ingress, persistence, ordering, fan-out, retry, deduplication, offline delivery |
| Scaling plan | connection routing, pub/sub or queues, partition by room/user, hot room handling |
| Failure modes | node death, reconnect, duplicate send, delayed delivery, out-of-order delivery, presence staleness |
| Trade-offs | strict ordering vs throughput, presence freshness vs traffic, push vs pull history |

Grade the result with the same dimensions as [method.md](../design-method/method.md):
requirements, estimates, API/data model, component choices, scaling bottlenecks,
consistency, operability, and explicit trade-offs.

## How to read the task

Read this as a realtime correctness problem. The design must cover persistent
connections, message persistence, room-level ordering, delivery retries,
idempotency, reconnect behavior, and presence fan-out. Transport is only one
part of the system.

## How to read the output

A strong design document names the source of truth for messages, the ordering key
for a room, and the mechanism that delivers messages to connected clients. It
should explain what happens when a gateway dies while clients are connected and
how clients resume from the last delivered message.

Read the artifact as a failure walkthrough. Pick one message id and follow it
through send, persist, fan-out, acknowledgement, retry, reconnect, and history
fetch. If the same message can be displayed twice, vanish after reconnect, or
arrive out of room order without an explanation, the design is incomplete.

## What to observe

1. **Connections are stateful** - horizontal scaling needs routing or pub/sub to reach the right socket.
2. **Ordering has a scope** - strict ordering is usually per room, not global.
3. **Retries require idempotency** - at-least-once delivery is usable only when duplicates are harmless.
4. **Presence can dominate traffic** - typing and online state need batching or throttling at scale.

For each message-flow step, write one sentence in this form:

```text
This step preserves _____ because the system records/checks _____.
```

## What you learned

- Chat design combines low-latency delivery with durable message history.
- Ordering, fanout, presence, and offline delivery pull the design in different directions.
- Queues and event streams can help, but they do not remove product-level delivery choices.
- A good chat design names which guarantees it provides and which it does not.

## Practice experiments

1. Redesign one-to-one chat as large group chat and identify what breaks first.
2. Add offline push notifications and decide whether they are part of the message
  transaction.
3. Require read receipts at scale and explain how receipt fan-out is bounded.

## Trade-offs

- **Ordering vs throughput** — strict per-room ordering serialises that room;
  partition by room to scale across rooms.
- **At-least-once + dedup vs exactly-once** — true exactly-once is impractical;
  at-least-once plus idempotent dedup is the pragmatic standard.
- **Presence cost** — naive presence fan-out is chatty; batch/debounce it.
- **Connection scale** — millions of sockets need sharded gateways and a pub/sub
  backbone; capacity is about concurrency, not QPS.

## Next steps

- [Event streaming](../event-streaming/README.md) for replayable message logs.
- [Message delivery semantics](../message-delivery-semantics/README.md) for duplicates and retries.
- [Observability](../observability/README.md) for operational signals in real-time systems.

## Further reading

- Alex Xu, *System Design Interview*, ch. "Design a Chat System".
- Referenced modules: [async queues](../async-queues/README.md),
  [message delivery semantics](../message-delivery-semantics/README.md).
- MDN, "The WebSocket API":
  https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API

## Cleanup

Only if profiles were started for prototyping:

```bash
make reset
```
