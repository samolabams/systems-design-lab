// API design: REST vs gRPC vs GraphQL.
// Dependency-free demonstration run inside the existing Node `app` container
// (piped to `node` over stdin). It shows the parts that are *measurable* without
// standing up gRPC/GraphQL servers: real Protobuf wire-size vs JSON, and how
// GraphQL field-selection collapses REST over-fetch and round trips. The section
// to print is chosen by the SECTION env var.

// ---- A sample domain object: a shortened link with nested click events. ------
const link = {
  slug: 'abc123',
  url: 'https://example.com/some/fairly/long/path?utm=spring',
  visits: 4096,
  clicks: [
    { ts: 1719772800, country: 'US' },
    { ts: 1719772860, country: 'GB' },
    { ts: 1719772920, country: 'DE' },
  ],
};

// ---- Minimal Protobuf wire encoder (proto3), enough for this message. --------
// message Link  { string slug=1; string url=2; uint64 visits=3; repeated Click clicks=4; }
// message Click { uint64 ts=1; string country=2; }
function varint(n) {
  const out = [];
  let v = BigInt(n);
  do { let b = Number(v & 0x7fn); v >>= 7n; if (v > 0n) b |= 0x80; out.push(b); } while (v > 0n);
  return Buffer.from(out);
}
const tag = (field, wtype) => varint((field << 3) | wtype);
function lenDelim(field, buf) {                       // wire type 2
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf, 'utf8');
  return Buffer.concat([tag(field, 2), varint(b.length), b]);
}
const varField = (field, n) => Buffer.concat([tag(field, 0), varint(n)]); // wire type 0
function encodeClick(c) {
  return Buffer.concat([varField(1, c.ts), lenDelim(2, c.country)]);
}
function encodeLink(l) {
  const parts = [lenDelim(1, l.slug), lenDelim(2, l.url), varField(3, l.visits)];
  for (const c of l.clicks) parts.push(lenDelim(4, encodeClick(c)));
  return Buffer.concat(parts);
}

function wire() {
  const json = Buffer.from(JSON.stringify(link), 'utf8');
  const proto = encodeLink(link);
  const pct = (100 * (json.length - proto.length) / json.length).toFixed(0);
  console.log('  Same Link record, two encodings on the wire:');
  console.log(`    REST/JSON  : ${json.length} bytes  ${JSON.stringify(link).slice(0, 48)}…`);
  console.log(`    gRPC/Proto : ${proto.length} bytes  0x${proto.toString('hex').slice(0, 40)}…`);
  console.log(`    Protobuf is ${pct}% smaller — binary, field numbers not names, varints.`);
  console.log('    (Cost: opaque on the wire; you need the .proto schema to read it.)');
}

function graphql() {
  // Client only needs slug + visits. REST returns the whole resource (over-fetch).
  const needed = { slug: link.slug, visits: link.visits };
  const full = Buffer.from(JSON.stringify(link), 'utf8').length;
  const tailored = Buffer.from(JSON.stringify(needed), 'utf8').length;
  console.log('  A client that needs only { slug, visits }:');
  console.log(`    REST  GET /links/abc123 -> ${full} bytes (whole object: url + all clicks too)`);
  console.log(`    GraphQL { link(slug:"abc123"){ slug visits } } -> ${tailored} bytes (exactly asked)`);
  console.log(`    Over-fetch eliminated: ${full - tailored} wasted bytes avoided.`);
  console.log('');
  // Round trips for a nested read: user -> 3 links -> 2 clicks each.
  console.log('  Reading a user with 3 links and their clicks:');
  console.log('    REST  : 1 (user) + 1 (links) + 3 (clicks per link) = 5 round trips (N+1)');
  console.log('    GraphQL: 1 request, server resolves the whole tree = 1 round trip');
  console.log('    (Cost: per-request shape defeats simple URL/CDN caching; needs query-cost limits.)');
}

function evolve() {
  console.log('  Additive change — add a "title" field — breaks no client IF you follow the rules:');
  console.log('    REST/JSON : add the key; old clients ignore unknown fields.');
  console.log('    gRPC/Proto: assign a NEW field number; never reuse/renumber. Old readers skip it.');
  console.log('    GraphQL   : add the field to the schema; only clients that select it receive it.');
  console.log('  Streaming (not encoded here): gRPC server-streaming pushes many messages over one');
  console.log('  HTTP/2 connection; REST needs SSE/polling for browser streams; GraphQL uses subscriptions.');
}

function choose() {
  console.log('  Choose by contract shape, not by framework popularity:');
  console.log('    REST    : public resource APIs, browser clients, URL caching, simple CRUD.');
  console.log('    gRPC    : internal service-to-service calls, low latency, typed contracts, streaming.');
  console.log('    GraphQL : product clients that need flexible read shapes across many resources.');
  console.log('');
  console.log('  For this URL shortener:');
  console.log('    POST /links and GET /links/{code} are naturally REST-shaped resources.');
  console.log('    A private analytics service ingesting click events could fit gRPC streaming.');
  console.log('    A dashboard combining links, owners, visits, and click breakdowns could fit GraphQL.');
}

function operate() {
  console.log('  Operational checklist once the contract is chosen:');
  console.log('    REST    : cache headers, pagination, status codes, idempotency keys, versioning.');
  console.log('    gRPC    : deadlines, retries, backoff, schema compatibility, load balancing, observability.');
  console.log('    GraphQL : query depth, resolver batching, per-field authorization, persisted queries, cost limits.');
  console.log('');
  console.log('  The API style is only the starting point. Production readiness depends on the');
  console.log('  guardrails around it: limits, compatibility rules, monitoring, and failure behavior.');
}

const section = process.env.SECTION || 'all';
if (section === 'wire' || section === 'all') wire();
if (section === 'graphql' || section === 'all') graphql();
if (section === 'evolve' || section === 'all') evolve();
if (section === 'choose' || section === 'all') choose();
if (section === 'operate' || section === 'all') operate();
