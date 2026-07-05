# infra/gateway — entry point, load balancing, and routing

The gateway is the first infrastructure component reached by each request. It
decides which app replica serves the request and can terminate TLS, apply rate
limits, and cache responses at the edge.

## What's here

- `nginx/nginx.conf` — the active gateway (base system). Uses a per-request DNS
  resolver so traffic spreads across all `app` replicas when you `make scale`.
- `nginx/variants/` — drop-in strategies (`round-robin`, `ip_hash`,
  `least_conn`) used during load balancing to compare load-balancing trade-offs.
- `haproxy/haproxy.cfg` — an alternative balancer with **active** health checks
  and a stats page, enabled by `make load-balancing-haproxy`.

## The lesson

Open Source Nginx detects a failed backend only *passively* after request
failures. HAProxy *actively* probes `/health` and removes an unhealthy node
before user traffic reaches it.

**Used in:** load balancing (load balancing), scaling (scaling), API gateway (API gateway).
