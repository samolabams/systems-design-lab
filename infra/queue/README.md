# infra/queue — async messaging (RabbitMQ)

A queue lets the API accept work and answer immediately (`202 Accepted`) while
**workers** process it out-of-band. Producers and consumers scale independently;
a traffic burst is absorbed by the queue instead of overwhelming the database.

## What's here

Nothing yet — RabbitMQ currently runs on its image defaults (see the `rabbitmq`
service in [../../docker-compose.yml](../../docker-compose.yml)). Custom config
(`rabbitmq.conf`, `definitions.json`, exchange/queue topology) lands here when a
lesson needs it.

## The lesson

**Backpressure:** workers pull with `prefetch(1)`, so throughput is added by
adding *workers*, not by increasing an unbounded buffer. Contrast with event streaming
(Kafka): a queue deletes a message once consumed; a log allows replay.

**Used in:** async queues (async processing & queues). Kafka/event-log in event streaming.
