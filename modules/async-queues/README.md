# Asynchronous Processing And Queues

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand queues as a general mechanism for
moving work out of the request path and controlling overload. You should be able
to explain:

1. Why slow or bursty work is often processed asynchronously.
2. What producers, brokers, queues, consumers, acknowledgements, and redelivery
   mean.
3. Why `202 Accepted` is different from completing the work synchronously.
4. How competing consumers increase throughput.
5. How prefetch and acknowledgements create backpressure.
6. Why at-least-once delivery requires idempotent handlers.
7. How a queue differs from the replayable event log in event streaming.

## What you will build or run

1. A RabbitMQ-backed queue connected to the reference app and worker.
2. A request that enqueues work and returns before the worker finishes it.
3. Queue depth and worker output that show buffering under load.
4. A failure/retry path that separates request success from background processing success.

## Why this matters

**A queue is a durable waiting line for messages between producers and
consumers.** It decouples request acceptance from work execution: the producer
records work now, and a worker processes it when capacity is available. Not
every unit of work belongs on the user-facing request path.
Sending an email, resizing an image, generating a report, calling a slow third
party, or processing a burst of jobs may take longer than the API should make a
client wait.

With a queue, the API can validate the request, publish a message, and return
`202 Accepted`. Workers process the backlog separately. That keeps the request
path responsive and gives the system a buffer during bursts.

Queues also make overload visible. Instead of every request immediately hitting a
slow dependency, the broker holds pending work and workers drain it at a
controlled rate. The trade-off is that the work finishes later, somewhere else,
and must be observable and retry-safe.

The concept is independent of any one broker. The lab uses RabbitMQ and worker
containers as one concrete implementation so the queue, acknowledgements,
redelivery, prefetch, and competing-consumer behavior are visible.

## Concept

A queue sits between a producer and consumers:

```text
producer -> broker queue -> consumers/workers
```

The producer publishes a message. The broker stores it until a consumer is ready.
A consumer receives the message, does the work, then acknowledges completion. If
the consumer dies before acknowledgement, the broker can redeliver the message.

Common queueing terms:

- **Producer** - the component that publishes work.
- **Broker** - the messaging system that stores and routes messages.
- **Queue** - an ordered waiting area for messages.
- **Consumer / worker** - a process that receives messages and performs work.
- **Acknowledgement (ack)** - a signal that the worker finished the message.
- **Redelivery** - sending an unacknowledged message again after failure.
- **Prefetch** - the maximum number of unacknowledged messages a worker may hold.
- **Backpressure** - a mechanism that prevents downstream workers from being
  overwhelmed by upstream producers.
- **Dead-letter queue (DLQ)** - a place for messages that cannot be processed
  after retries.
- **Idempotent handler** - a worker operation that is safe to repeat.

The basic asynchronous request flow is:

```text
client sends request
API validates and publishes a job message
API returns 202 Accepted
worker consumes the message later
worker acknowledges after successful processing
```

Queues usually provide **at-least-once delivery**: the broker tries not to lose
messages, but a worker may see the same message more than once. That is why
worker handlers should be idempotent. Re-running the same job should not corrupt
state or charge a customer twice.

Queues and logs solve different problems:

| Mechanism | Main idea | Good fit |
|---|---|---|
| Queue | distribute work; delete after ack | do this task once |
| Event log | retain ordered events for replay | let many readers process history |

This module covers the queue model. [Event streaming](../event-streaming/README.md)
covers the event log model.

## How it works

The general roles are represented by local lab components:

| General role | Lab implementation |
|---|---|
| producer | URL-shortener app endpoint `POST /jobs`, exposed by the gateway as `POST /api/jobs` |
| broker | RabbitMQ |
| queue | `jobs` queue |
| consumers | scalable `worker` containers |
| backpressure setting | worker prefetch of 1 |
| observability | worker logs and RabbitMQ management UI |

The `async-queues` profile starts RabbitMQ and one worker. The app exposes an
internal `POST /jobs` route, and the gateway exposes it publicly as
`POST /api/jobs`. When the endpoint receives a job request, it publishes a
message to the `jobs` queue and returns `202` immediately. The request path does
not do the slow work.

Workers consume from the queue with prefetch set to 1. That means each worker can
hold at most one unacknowledged message at a time. If a burst of jobs arrives,
RabbitMQ holds the backlog while workers drain steadily. Scaling the worker
service adds more competing consumers.

If a worker dies after receiving a message but before acknowledging it, RabbitMQ
can redeliver that message to another worker. That protects against lost work,
but it also means the handler must be idempotent: processing the same job twice
should not create two permanent side effects. Prefetch controls how much work can
be in this risky in-flight state. A larger prefetch can improve throughput for
fast jobs, but it can also let one worker hoard messages while others sit idle.

When reading this module, keep these layers separate:

```text
API endpoint -> accepts work and publishes a message
broker queue -> buffers messages and handles delivery
worker       -> performs work and acknowledges completion
logs/UI      -> show backlog, distribution, and completion
```

If behavior is confusing, ask where the job is now: accepted by the API, waiting
in the queue, unacknowledged by a worker, completed, or redelivered.

## Run

Run these commands from the repository root:

```bash
```

The output should end with:

```text
systems-design
```

Start the queue profile:

```bash
make async-queues
```

Then run the guided demo:

```bash
./modules/async-queues/demo.sh
```

The RabbitMQ management UI is available at `http://localhost:15672` with local
lab credentials `app` / `app`.

## How to read the commands

Publishing a job has this shape:

```bash
curl -s -X POST http://localhost:8080/api/jobs \
  -H 'Content-Type: application/json' \
  -d '{"task":"resize","id":1}'
```

Read that as:

| Part | Meaning |
|---|---|
| `POST /api/jobs` | ask the gateway to route an enqueue request to the app |
| JSON body | the job payload |
| `202 Accepted` | the work was accepted for async processing |

Scaling workers has this shape:

```bash
docker compose --profile async-queues up -d --scale worker=3
```

Read that as: run three worker containers that compete for messages from the same
queue.

Inspecting logs has this shape:

```bash
docker compose --profile async-queues logs --tail 30 worker
```

Read that as: show recent worker activity, including which worker started and
completed each job.

## How to read the output

An API response such as:

```json
{"status":"enqueued"}
```

means the API accepted the job and published a message. It does not mean the job
has already finished.

Worker log lines such as `job_start` and `job_done` show asynchronous execution.
Different worker hostnames prove the competing-consumers pattern: several
workers are pulling from the same queue.

In the RabbitMQ UI, watch these queue fields:

| Field | Meaning |
|---|---|
| Ready | messages waiting for a worker |
| Unacked | messages delivered but not yet acknowledged |
| Total | ready plus unacknowledged messages |

If Ready rises during a burst and then falls as workers finish, the queue is
absorbing load and draining it over time.

## What to observe

1. **The API returns quickly** - `POST /jobs` returns `202` after enqueueing,
   before the worker finishes.
2. **Workers process asynchronously** - worker logs show `job_start` and
   `job_done` after the API response.
3. **Competing consumers share work** - scaling to three workers spreads jobs
   across worker hostnames.
4. **The broker absorbs bursts** - a burst increases queue depth instead of
   overwhelming one worker.
5. **Prefetch limits in-flight work** - each worker holds only a small number of
   unacknowledged messages.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves processing is asynchronous because the API returned 202 before job_done appeared.
```

## What you learned

- Queues absorb bursts by moving slow work out of the request path.
- A queued job still needs ownership, retries, idempotency, and failure handling.
- Queue depth is a pressure signal, not just an implementation detail.
- Async processing improves responsiveness but introduces delayed completion.

## Practice experiments

After the guided demo, make one change at a time and predict the effect before
running the command again:

1. **Scale workers down.** Run one worker and publish a burst. Watch Ready grow
   higher than with three workers.
2. **Scale workers up.** Run three workers and compare how quickly the queue
   drains.
3. **Publish a larger burst.** Send 50 jobs and watch Ready and Unacked in the
   RabbitMQ UI.
4. **Inspect logs by worker.** Identify which worker hostnames completed jobs.
5. **Design an idempotency key.** Decide what field in the job payload could be
   used to avoid processing a duplicate job twice.

## Trade-offs

- **Queues improve responsiveness but add asynchrony.** The API can return
  quickly, but the work is not complete yet.
- **At-least-once delivery needs idempotency.** Redelivery prevents lost work but
  can produce duplicates.
- **Prefetch is a throughput/fairness knob.** Higher prefetch can keep workers
  busier, but lower prefetch makes slow workers less likely to hold many jobs.
- **Backlog is useful only if it is monitored.** Queue depth, age, retries, and
  DLQs need alerts.
- **Queues do not make slow work disappear.** They move work out of the request
  path and smooth bursts, but total work still has to be processed.
- **Queue vs log matters.** Use queues for task distribution. Use event logs,
  like event streaming, when multiple consumers need replayable history.

## Next steps

- [Message delivery semantics](../message-delivery-semantics/README.md) for duplicates, retries, and idempotency.
- [Sagas](../sagas/README.md) for multi-step workflows.
- [Observability](../observability/README.md) for measuring queues and workers.

## Further reading

- RabbitMQ tutorials, "Work Queues":
  https://www.rabbitmq.com/tutorials/tutorial-two-python
- RabbitMQ, "Consumer Prefetch": https://www.rabbitmq.com/docs/consumer-prefetch
- Enterprise Integration Patterns, "Competing Consumers":
  https://www.enterpriseintegrationpatterns.com/patterns/messaging/CompetingConsumers.html
- Enterprise Integration Patterns, "Dead Letter Channel":
  https://www.enterpriseintegrationpatterns.com/patterns/messaging/DeadLetterChannel.html

## Cleanup

```bash
make reset
```
