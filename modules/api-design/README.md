# API design: REST vs gRPC vs GraphQL

**Track:** Components
**Prerequisites:** none

> **Status:** Demonstration - a dependency-free Node script measures Protobuf vs
> JSON wire size and GraphQL field selection. It does not start live gRPC or
> GraphQL servers; it isolates the contract properties this module demonstrates.

## Outcome

After this module, you should evaluate API style as a contract-design
decision, not as a framework preference. You should be able to explain:

1. How REST, gRPC, and GraphQL model the client-server contract differently.
2. Why wire format, schema, caching, browser reach, and query shape matter.
3. What over-fetching, under-fetching, and N+1 requests mean.
4. Why Protobuf is compact and schema-first.
5. How additive schema evolution avoids breaking existing clients.
6. How to choose an API style based on access pattern and consumer needs.

## What you will build or run

1. A side-by-side comparison of REST/JSON, gRPC/Protobuf-style payloads, and GraphQL-style field selection.
2. Example requests and responses that show payload shape, coupling, and client control.
3. A small schema-evolution scenario that shows why API compatibility matters.
4. A decision checklist for choosing an API style from requirements instead of habit.

## Why this matters

The contract between client and server is a long-lived decision: it shapes
payload size, latency, how the API evolves without breaking clients, and how easy the
API is to consume. REST, gRPC, and GraphQL each optimise for a different shape of
problem, and picking the wrong one shows up later as over-fetching, chatty round
trips, or painful versioning.

## Concept

- **REST/JSON** — using HTTP verbs (GET, POST, PUT, DELETE) to act on named
  resources (nouns like `/links/abc`); ubiquitous, human-readable, cacheable by
  URL; but over/under-fetching and chatty for nested data.
- **gRPC/Protobuf** — where REST is *resource*-centric (act on nouns), gRPC is
  *procedure*-centric: you call named methods (`GetLink`, `CreateLink`) like a
  local function. Binary, schema-first (defined in an **IDL** — Interface
  Definition Language — a `.proto` file both sides compile against), runs over
  **HTTP/2** (a multiplexed, streaming version of HTTP), small + fast; great
  service-to-service, weaker for browsers and ad-hoc querying.
- **GraphQL** — the client specifies exactly the fields it wants in one request;
  kills over-fetching and round trips, but caching is harder and a careless query
  can be expensive. Two named hazards: **N+1** (fetching a list, then firing one
  more query *per item* — 1 + N queries instead of one) and **depth attacks** (a
  deeply nested query that explodes into huge work).
- **Cross-cutting** — versioning (URL vs field deprecation vs proto field numbers),
  pagination (offset vs cursor), idempotency, and error semantics.

## How it works

Standing up real gRPC and GraphQL servers drags in heavy toolchains, so the demo
instead measures the parts that are *quantifiable* with a dependency-free Node
script (`compare.js`) run **inside the existing `app` container** (`node` reads
the program from stdin). The script:

- Encodes the **same** `Link` record as JSON and as real **Protobuf** wire bytes
  (a minimal proto3 encoder: varints, field numbers, length-delimited strings)
  and prints both sizes.
- Shows a client that needs only `{ slug, visits }`: REST returns the whole
  resource (over-fetch) while a **GraphQL** selection returns exactly those
  fields, and counts the round trips for a nested read (REST N+1 vs one GraphQL
  request).
- Walks the **additive schema change** rules for each contract, and notes where
  streaming fits (gRPC server-streaming vs **SSE** — Server-Sent Events, a
  one-way stream from server to browser — or plain polling).
- Ends with a selection rule: REST for public resource APIs and cacheable browser
  paths, gRPC for internal typed calls and streaming, GraphQL for flexible read
  shapes across many resources.
- Finishes with the operational guardrails each style needs: cache semantics and
  idempotency for REST, deadlines and compatibility for gRPC, query limits and
  resolver batching for GraphQL.

The qualitative axes the lab cannot quantify — human-readability, caching,
*browser reach* (whether a browser can call it directly — gRPC needs a gRPC-Web
proxy), build-time coupling — are called out inline as trade-offs.

## Run

```bash
pwd
make api-design
./modules/api-design/demo.sh
```

Run non-interactively with `AUTO=1 ./modules/api-design/demo.sh`.

The output of `pwd` should end with `systems-design`.

## How to read the commands

The demo runs `compare.js` inside the existing app container. No separate REST,
gRPC, or GraphQL server is started. Read the commands as controlled measurements
of contract properties:

| Demo section | What it measures |
|---|---|
| wire | JSON bytes versus Protobuf wire bytes for the same record |
| graphql | field selection and round-trip count |
| evolve | additive schema changes and streaming options |
| choose | which API style fits which access pattern |
| operate | operational guardrails after choosing an API style |

## How to read the output

If Protobuf is smaller than JSON, that demonstrates the effect of binary field
numbers and compact varint encoding. If the GraphQL selection returns fewer
fields than the REST representation, that demonstrates how client-selected fields
avoid over-fetching.

Round-trip counts should be read as a model of access pattern cost: one nested
GraphQL request can replace a REST request followed by one request per child
resource, but GraphQL shifts complexity into query planning and cost control.

## What to observe

1. The Protobuf encoding of the record is about **half** the size of the
   equivalent JSON (binary, field numbers instead of names, varints).
2. A GraphQL selection returns only the requested fields — the over-fetched
   bytes REST sends are eliminated.
3. A nested read is one GraphQL round trip vs REST's N+1.
4. An additive field breaks no clients under all three contracts if the design
  follows each contract's evolution rules.
5. The same product may expose more than one API style: REST for the public URL
  shortener, gRPC for internal click ingestion, GraphQL for a dashboard.
6. The style choice is incomplete without production guardrails: limits,
   compatibility rules, monitoring, and failure behavior.

## What you learned

- API style is a product and operations decision, not only a syntax choice.
- REST, gRPC, and GraphQL optimize for different client, performance, and evolution needs.
- Schema evolution and compatibility rules matter as soon as clients are outside your deploy cycle.
- Operational concerns such as caching, observability, and failure handling are part of API design.

## Practice experiments

1. Add a field to the example record and predict which clients should ignore it.
2. Decide whether a browser-heavy product should expose gRPC directly or through
   another interface.
3. Identify one endpoint in the lab that is naturally REST-shaped.
4. Describe a query that would need GraphQL depth or cost limits.
5. Pick one API style and list the first three guardrails you would add before
  exposing it to production traffic.

## Trade-offs

- **Human-friendly vs efficient** — JSON is debuggable and cache-friendly;
  Protobuf is compact and strongly typed but opaque on the wire.
- **Flexibility vs cacheability** — GraphQL's per-request shape defeats simple
  HTTP/CDN caching and needs query cost limits.
- **Browser reach** — gRPC needs gRPC-Web/a proxy for browsers; REST/GraphQL run
  natively.
- **Coupling** — schema-first (gRPC/GraphQL) catches breakage at build time; REST
  relies on discipline and docs.

## Next steps

- [API gateway](../api-gateway/README.md) for where APIs enter the system.
- [Rate limiting](../rate-limiting/README.md) for protecting public APIs.
- [Observability](../observability/README.md) for measuring API behavior.

## Further reading

- Google, "gRPC Introduction": https://grpc.io/docs/what-is-grpc/introduction/
- "GraphQL — Introduction": https://graphql.org/learn/
- Roy Fielding, REST dissertation, ch. 5:
  https://ics.uci.edu/~fielding/pubs/dissertation/rest_arch_style.htm
- Protocol Buffers overview: https://protobuf.dev/overview/

## Cleanup

```bash
make reset
```
