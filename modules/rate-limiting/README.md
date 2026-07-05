# Rate limiting

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand rate limiting as a general
capacity-protection mechanism with clear algorithmic choices. You should be able
to explain:

1. Why rate limiting is a form of load shedding.
2. How token bucket, leaky bucket, fixed window, and sliding window limiters
  differ.
3. Why edge limiting and application-level limiting solve different problems.
4. Why distributed application replicas need a shared counter.
5. What `429 Too Many Requests` means.
6. How burst size, refill rate, and fail-open/fail-closed behavior affect users.

## What you will build or run

1. A rate-limited request path that allows normal traffic and rejects excess traffic.
2. Requests that show quota windows, counters, and `429` responses.
3. A comparison between per-client limits and system-wide protection.
4. A tuning exercise for threshold, window, and enforcement location.

## Why this matters

A single misbehaving client — a retry storm, a scraper, a runaway script, or an
attacker — can consume all available capacity and take the service down for everyone.
Rate limiting caps how fast any one caller may consume resources, returning
**429 Too Many Requests** for traffic over the configured quota while preserving
capacity for admitted requests. It is the cheapest form of load shedding.

## Concept

- **Token bucket** — tokens accumulate at a fixed refill rate up to a maximum
  capacity. Each request spends one token. The capacity controls the allowed
  burst; the refill rate controls the long-term average rate.
- **Leaky bucket** — requests enter a queue or counter and leave at a fixed drain
  rate. Excess requests are delayed or dropped when the bucket is full. This
  smooths traffic into a steadier output rate. Nginx's `limit_req` uses this
  style of algorithm.
- **Fixed window** — count requests per key (IP, API key, user) within a fixed
  clock interval and reject once the count exceeds the quota. It is simple, but
  a client can burst across a boundary between two windows.
- **Sliding window** — count requests over the trailing N seconds instead of a
  fixed clock interval. It gives smoother enforcement, but it tracks more state.
  A common implementation is an expiring counter or timestamp set.
- **Where to limit** —
  - **At the edge / gateway:** low-cost, coarse, per-IP. Sheds floods *before* they
    reach the app or database. First line of defence.
  - **In the app:** fine-grained, per-API-key or per-user, can apply business
    rules. More expensive (the request already arrived).
- **Why a shared store** — with N app replicas, an **in-memory** counter lets each
  replica admit the full quota, so the real limit becomes **N × quota**. A
  **shared counter in Redis** keeps the quota global.

Edge and application limiters provide complementary, layered protection:

```text
client -> edge limiter -> app/user limiter -> service logic -> dependencies
```

Edge limiting provides cheap, coarse protection such as per-IP flood control.
Application-level limiting provides precise policies such as per-user,
per-tenant, per-plan, or per-endpoint quotas.
Many production systems use both: the edge rejects obvious excess before it costs
application work, and the app enforces the business rule the edge cannot know.

## How it works

The concept is independent of any one gateway or shared store. The lab uses
Nginx for edge limiting and Redis for a shared application-level counter so both
layers are visible:

1. **Gateway (Nginx `limit_req`)** — we swap in
   `infra/gateway/nginx/variants/rate-limit.conf` (a `limit_req_zone` keyed by
   client IP, `rate=5r/s`, `burst=5 nodelay`, `limit_req_status 429`) and hot-reload
   Nginx. A flood from one IP gets a few `200`s then `429`s — the rejected
   requests never touch the app.
2. **Distributed primitive (Redis)** — we run the textbook fixed-window check
   directly against Redis: `INCR ratelimit:<user>` (atomically add 1 to the
   per-user counter, creating it at 0 if absent) plus `EXPIRE` (set the counter's
   TTL) on the first hit. Because every replica increments the **same** key, the
   quota is global. This is exactly what an app-level limiter middleware would do
   per request.

## Run

```bash
pwd
make rate-limiting
./modules/rate-limiting/demo.sh
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

The first half of the demo swaps the Nginx gateway configuration to enable
`limit_req`. Read repeated `curl` commands as a controlled flood from one client.
Status `200` means admitted; status `429` means rejected by the limiter.

The second half uses Redis directly:

```text
INCR ratelimit:<user>
EXPIRE ratelimit:<user> 10
```

Read that as a fixed-window counter. `INCR` is the atomic count. `EXPIRE` bounds
the time window so the quota resets.

## How to read the output

A sequence with early `200`s followed by `429`s proves the gateway admitted the
configured burst and rejected the overflow. A later trickle of `200`s proves the
bucket refilled.

Redis counts such as `req 6 -> count 6 DENY` prove the application-level quota is
being enforced by a shared counter rather than local process memory.

## What to observe

1. **Baseline** — with no limit, all 12 requests return `200`.
2. **Edge shedding** — after enabling `limit_req`, a 20-request flood returns a
   handful of `200`s and the rest `429` — the burst is absorbed, the overflow
   rejected immediately (`nodelay`).
3. **Refill** — wait a moment and trickle requests in under the rate; they pass
   again. The bucket leaks at a steady rate.
4. **Global counter** — the Redis `INCR` returns a running count; requests 1–5
   `ALLOW`, 6–7 `DENY`. `TTL` shows the window shrinking toward 0, after which the
   key expires and a fresh window begins.

## What you learned

- Rate limiting protects a system by controlling how many requests are accepted.
- The key, limit, and time window define the real policy.
- Rejecting excess work can be healthier than letting every dependency overload.
- Distributed rate limiting adds shared-state and consistency trade-offs.

## Practice experiments

1. Change the burst in the gateway config and predict how many requests pass.
2. Compare a fast flood with a slow trickle under the configured rate.
3. Design limiter keys for anonymous users, authenticated users, and API keys.
4. Decide whether the app should fail open or fail closed if Redis is down.

## Trade-offs

- **Burst vs strictness** — a larger burst is friendlier to legitimate spikes but
  lets more through before limiting; `nodelay` rejects fast, without `nodelay`
  Nginx trickles the burst out at the steady rate (smoothing, added latency).
- **Fixed window boundary effect** — a fixed window allows up to 2× the quota
  across a window boundary (end of one window + start of the next). Sliding-window
  or token-bucket algorithms smooth this out at higher cost.
- **Edge vs app** — the gateway is low-cost but blunt (per-IP, and many users can
  share one NAT IP); the app is precise (per-key) but pays to receive the request.
  Real systems use both.
- **Shared store is a dependency** — a Redis-backed limiter adds a network hop and
  a failure mode; decide whether to **fail-open** (allow on Redis outage, favour
  availability) or **fail-closed** (reject, favour protection).

## Next steps

- [API gateway](../api-gateway/README.md) for boundary enforcement.
- [Distributed rate limiter](../distributed-rate-limiter/README.md) for a full-system design.
- [Circuit breakers](../circuit-breakers/README.md) for downstream failure protection.

## Further reading

- Nginx, "Rate Limiting with NGINX":
  https://blog.nginx.org/blog/rate-limiting-nginx
- Nginx `ngx_http_limit_req_module` reference:
  https://nginx.org/en/docs/http/ngx_http_limit_req_module.html
- Stripe, "Scaling your API with rate limiters":
  https://stripe.com/blog/rate-limiters
- Redis, "Rate limiting" patterns (INCR): https://redis.io/glossary/rate-limiting/

## Cleanup

```bash
make reset
```
