# Edge Caching And CDN Model

**Track:** Components
**Study role:** Specialized - use when designs need public/static content delivery, origin offload, or global latency reduction.
**Prerequisites:** [Caching](/modules/caching/)

## Outcome

After this module, you should understand edge caching as the network-edge
version of caching, not as an unrelated infrastructure category. You should be
able to explain:

1. What an edge cache does: it stores cacheable HTTP responses close to clients
   or in front of an origin service.
2. Why CDNs reduce latency, origin load, and bandwidth pressure.
3. What cache hit, cache miss, cache key, freshness, and revalidation mean at the
   HTTP edge.
4. Why public and private content must be cached differently.
5. How TTL, `Cache-Control`, validators, and purge/versioning affect freshness.
6. Why edge caching pairs naturally with object storage from object storage.
7. Why Nginx is only the local lab implementation of the CDN pattern.

## What you will build or run

1. An edge cache path in front of an origin service.
2. Requests that show cache misses, cache hits, and response headers.
3. A cache-control scenario that changes freshness and reuse behavior.
4. A comparison between edge caching and application-level caching.

## Why this matters

**Edge caching is the system design pattern of answering repeated HTTP requests
before they reach the origin.** The origin is the backend service or storage
system that owns the response. If every request for the same static asset,
product image, public page, or downloadable file reaches the origin, the system
pays avoidable latency, compute, and bandwidth cost.

A Content Delivery Network (CDN) moves cached responses closer to users. The
concept is independent of any one proxy or CDN provider. In a real global
deployment, CDN points of presence sit in many regions. In this lab, one local
Nginx process plays the edge role so the mechanism is visible: the first request
is a miss, the edge fetches from the origin, and later requests are served from
the edge cache.

Edge caching is related to caching, but the placement is different. Caching puts
a cache near the application data path. Edge caching puts a cache in the HTTP delivery
path, before the origin. That makes it especially useful for public/static
content, object storage delivery, API responses that are safe to cache, and
traffic spikes where many users request the same resource.

Edge caching does not remove the need for authorization, invalidation, or origin
design. It shifts repeated reads away from the origin when the response is safe
to reuse.

## Concept

An edge cache is an HTTP cache that sits between clients and an origin:

```text
client -> edge cache -> origin
```

The edge stores responses by **cache key**. A cache key is the identity of a
request for caching purposes. It usually includes method, scheme, host, path, and
sometimes selected headers or query parameters.

Common edge caching terms:

- **Origin** - the backend service or object store that owns the response.
- **Edge** - a proxy/cache close to clients or in front of the origin.
- **CDN** - Content Delivery Network, a distributed set of edge locations.
- **Cache hit** - the edge has a fresh response and returns it without contacting
  the origin.
- **Cache miss** - the edge does not have a usable response, so it fetches from
  the origin and may store the result.
- **Cache key** - the request identity used to decide whether two requests can
  share a cached response.
- **Freshness lifetime / TTL** - how long a cached response is considered fresh.
- **Revalidation** - after a cached response becomes stale, the edge asks the
  origin whether it can still reuse that response. HTTP caches commonly use
  conditional requests with `If-None-Match`/`ETag` or
  `If-Modified-Since`/`Last-Modified`; the origin can reply `304 Not Modified`
  to reuse the cache entry or `200 OK` with a new response.
- **Purge / invalidation** - explicitly removing a cached response before its TTL
  expires.
- **Versioned asset** - a URL containing a content hash, such as
  `/app.abc123.css`, so new content gets a new cache key.

The basic edge cache flow is:

```text
request arrives at edge
if fresh cache entry exists: return HIT
if no entry exists: fetch origin, store response, return MISS
if entry is stale: revalidate or refetch, then return updated response
```

Cacheability is a correctness decision. Public content can often be cached at a
shared edge. Personalized or authenticated content must either bypass the shared
cache or vary the cache key carefully. A wrong cache key can leak one user's data
to another user.

Object storage and edge caching often work together:

```text
client -> CDN edge -> object store origin
```

Object storage introduced object storage for durable blobs. Edge caching shows why those blobs are
often served through an edge cache rather than directly from the origin for every
request.

## How it works

The general roles are represented by local lab components:

| General role | Lab implementation |
|---|---|
| client | `curl` from your host |
| edge cache | `edge`, an Nginx reverse proxy with `proxy_cache` |
| origin | the normal gateway at `localhost:8080` |
| origin replicas | scaled URL-shortener app containers |
| cache observability | `X-Cache-Status` response header |

The `edge-caching` profile starts a second Nginx process named `edge`. It
proxies requests to the gateway and stores selected responses using Nginx
`proxy_cache`. The lab adds an `X-Cache-Status` header so you can see whether a
response was a `MISS`, `HIT`, or `EXPIRED`.

The demo scales the app to three replicas and uses `/health` as the visible
origin response. `/health` includes the hostname of the app replica that served
the request. When you hit the origin gateway directly, the hostname can rotate
because the gateway load-balances across replicas. When you hit the edge after a
cache fill, the hostname stays the same because the edge is returning the cached
response instead of asking the origin again.

When reading this module, keep these layers separate:

```text
gateway/origin -> computes or fetches the response
edge cache     -> stores reusable HTTP responses
cache key      -> decides which requests share an entry
headers        -> communicate cache behavior and freshness
client         -> receives the response from edge or origin
```

If behavior is surprising, first ask whether the response is cacheable, then ask
which cache key was used, then ask whether the cached entry is fresh or expired.

## Run

Run these commands from the repository root:

```bash
```

The output should end with:

```text
systems-design
```

Start the edge caching profile:

```bash
make edge-caching
```

Then run the guided demo:

```bash
./modules/edge-caching/demo.sh
```

The demo pauses between steps. At each step, read the prediction, read the
command, and inspect the headers. The goal is not to memorize Nginx syntax; the
goal is to connect HTTP cache behavior to origin offload.

The local endpoints are:

```text
edge:   http://localhost:8082
origin: http://localhost:8080
```

## How to read the commands

Direct origin requests have this shape:

```bash
curl -s http://localhost:8080/health
```

Read that as: bypass the edge and ask the origin gateway directly.

Edge requests have this shape:

```bash
curl -si http://localhost:8082/health
```

Read that as:

| Part | Meaning |
|---|---|
| `curl` | make an HTTP request |
| `-s` | quiet progress output |
| `-i` | include response headers |
| `http://localhost:8082/health` | ask the edge cache for `/health` |

The demo filters output with:

```bash
grep -Ei 'X-Cache-Status|"host"'
```

That keeps the two proof points: the cache status header and the origin replica
hostname embedded in the response body.

## How to read the output

An edge response may include:

```text
X-Cache-Status: MISS
{"host":"app-abc123","role":"app"}
```

Read that as: the edge did not have a fresh response, so it asked the origin and
stored the result.

A later response may include:

```text
X-Cache-Status: HIT
{"host":"app-abc123","role":"app"}
```

Read that as: the edge served the cached response. The repeated hostname is the
proof: the request did not reach a newly selected origin replica.

After the TTL expires, you may see `EXPIRED` or a new `MISS`. That means the
edge had a stale entry and had to refresh or revalidate with the origin.

## What to observe

1. **Origin requests rotate** - direct gateway calls can show different app
   hostnames because the origin tier is load-balanced.
2. **The first edge request is a miss** - `X-Cache-Status: MISS` means the edge
   had to fetch from the origin.
3. **Repeated edge requests become hits** - `X-Cache-Status: HIT` and the same
   `host` prove the origin is not touched.
4. **TTL controls freshness** - after the configured TTL expires, the next edge
   request refreshes the cached response.
5. **Edge caching reduces origin load** - many client requests can collapse into
   one origin request for the same cache key.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves the edge served from cache because X-Cache-Status is HIT and the host did not change.
```

## What you learned

- Edge caching moves repeated reads closer to clients and away from the origin.
- Cache keys and headers decide what can be reused safely.
- Freshness and invalidation are design choices, not automatic guarantees.
- CDN behavior is useful for static assets, public objects, and expensive repeated reads.

## Practice experiments

After the guided demo, make one change at a time and predict the effect before
running the command again:

1. **Bypass the edge.** Compare several `curl http://localhost:8080/health`
   responses with several edge responses.
2. **Watch TTL behavior.** Request through the edge, wait longer than the TTL,
   then request again and identify the changed cache status.
3. **Change the URL.** Request a different path and explain why it creates a
   different cache key.
4. **Think about private data.** Describe why a user-specific `/profile` response
   should not be cached with the same key for every user.

## Trade-offs

- **Freshness vs origin load.** Longer TTLs reduce origin requests but increase
  the chance of serving stale responses.
- **Invalidation is operational work.** Purge APIs, short TTLs, and versioned
  asset URLs are common ways to roll out changes safely.
- **Cache keys are security boundaries.** If personalized responses share a
  public cache key, data can leak across users.
- **CDNs add another layer.** They improve latency and absorb spikes, but they
  must be monitored, configured, and debugged like any other production system.
- **Not every response is cacheable.** Unsafe methods, user-specific responses,
  and `Cache-Control: no-store` content should bypass shared edge caches.

## Next steps

- [Caching](/modules/caching/) for application-side cache patterns.
- [Object storage](/modules/object-storage/) for blob origins.
- [DNS](/modules/dns/) for how clients find edge entry points.

## Further reading

- MDN, "HTTP caching": https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching
- Cloudflare, "What is a CDN?":
  https://www.cloudflare.com/learning/cdn/what-is-a-cdn/
- Nginx, "A Guide to Caching with NGINX":
  https://blog.nginx.org/blog/nginx-caching-guide
- Nginx `proxy_cache` reference:
  https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache

## Cleanup

```bash
make reset
```
