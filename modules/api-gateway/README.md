# API Gateway / Edge Gateway

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand an API gateway as the public entry
point for API traffic rather than an abstract diagram label. You should be able to explain:

1. What an API gateway does: it receives external requests and forwards them to internal services.
2. Why systems use a gateway: it gives clients one stable entry point while hiding internal service layout.
3. The difference between an API gateway, a reverse proxy, and a load balancer.
4. Which responsibilities commonly belong at the gateway: routing, TLS termination, authentication boundary, rate limiting, request headers, logging, and policy enforcement.
5. Which responsibilities should usually stay out of the gateway: business rules and domain-specific application logic.
6. How the gateway in this lab forwards requests to the app service.
7. How to inspect gateway behavior with `curl` and the Nginx config.

## What you will build or run

1. A running Nginx gateway that exposes one public entry point on `localhost:8080`.
2. Requests that prove which responses come from the gateway and which come from the app.
3. Header and route inspections that show how public paths map to internal services.
4. A comparison point for load balancing and rate limiting modules that build on the same edge.

## Why this matters

**An API gateway is a public entry point for client traffic.** In many systems, clients do not call every internal service directly. They call one stable endpoint, and that endpoint decides where the request should go inside the system.

Without a gateway, every client would need to know internal service addresses, ports, protocols, and deployment changes. That creates tight coupling: changing an internal service can force changes in clients. With a gateway, clients talk to one stable address while the system keeps its internal layout private.

A gateway also gives the system one place to apply cross-cutting behavior before requests reach application code. Common examples include:

- routing requests to the right service
- terminating HTTPS/TLS
- enforcing authentication or authorization checks
- applying rate limits
- adding or preserving request headers
- collecting access logs and metrics
- handling API versions or path-based routing

The concept is independent of any one gateway product. The lab uses the existing
Nginx gateway in the base stack as one concrete implementation. The gateway is
already the only public entry point to the app. The app runs on the internal
Docker network; the host reaches it through the gateway.

## Concept

A basic API gateway request path looks like this:

```text
client -> API gateway -> internal service
```

The client sees the gateway. The internal service sees a request forwarded by the gateway. The gateway is not the business application itself; it is infrastructure on the request path.

The main vocabulary:

- **Client** - the caller, such as a browser, mobile app, script, or another service.
- **API gateway** - the public entry-point component that receives external API traffic and applies routing or policy before forwarding it.
- **Reverse proxy** - a proxy that sits in front of servers and forwards client requests to them. An API gateway is often a reverse proxy with API-specific responsibilities.
- **Load balancer** - a component that chooses which replica should receive traffic. A gateway may include load balancing, but load balancing is only one gateway responsibility.
- **Backend service** - the internal service that actually handles the request.
- **Route** - a rule that maps an incoming path, host, or method to a backend.
- **Policy** - a rule applied at the gateway, such as rate limits, authentication, CORS, or header handling.

## Gateway vs load balancer

Load balancing and API gateway behavior often live in the same tool, but they answer different questions.

| Component | Main question it answers |
|---|---|
| Load balancer | Which healthy backend replica should handle this request? |
| API gateway | What should happen to this API request before it reaches an internal service? |

load balancing focuses on distribution across replicas. This module focuses on gateway behavior: one public entry point, request forwarding, route ownership, headers, and gateway policy.

## What should live at the gateway

Good gateway responsibilities are cross-cutting. They apply to many services or to the system boundary itself:

- **Routing** - send `/api/users` to one service and `/api/orders` to another.
- **TLS termination** - decrypt HTTPS at the edge so certificates are managed in one place.
- **Authentication boundary** - verify identity before traffic enters the internal network.
- **Rate limiting** - protect services from too many requests. This guide covers that deeply in rate limiting.
- **Request headers** - preserve client information with headers such as `X-Forwarded-For`.
- **Logging and metrics** - record who called what, when, and how long it took.
- **Version routing** - send `/v1/...` and `/v2/...` to different implementations during migrations.

Avoid putting business logic in the gateway. Domain rules such as "can this user cancel this order?" usually belong in the service that owns that domain. A gateway should enforce boundary policy; it should not become the application.

## How it works

The base stack already has an Nginx gateway:

```text
host curl -> gateway (Nginx, port 8080) -> app (internal port 3000)
```

The gateway is published on the host at `localhost:8080`. The app is not published on the host. The app is reachable from the gateway over the internal Docker network by the service name `app:3000`.

The gateway now owns a small public API route map:

| Public gateway route | Internal app route | Purpose |
|---|---|---|
| `/gateway-health` | none; answered by Nginx | prove the gateway itself is alive |
| `/api/health` | `/health` | app health and replica identity |
| `/api/metrics` | `/metrics` | app metrics endpoint |
| `/api/shorten` | `/shorten` | create a short URL code |
| `/api/jobs` | `/jobs` | enqueue a background job when the queue profile is active |
| `/api/links/<code>` | `/<code>` | resolve a short code and return the redirect |

The older catch-all route still exists for compatibility with other modules, but this lesson uses the explicit `/api/*` routes so the gateway route map is visible.

The important files are:

| File | Role in the lab | What to inspect |
|---|---|---|
| [infra/gateway/nginx/nginx.conf](../../infra/gateway/nginx/nginx.conf) | Active gateway config | `listen 80`, `location`, `proxy_pass`, forwarded headers, timeouts |
| [apps/url-shortener/src/routes/index.js](../../apps/url-shortener/src/routes/index.js) | App route table | `/health`, `/metrics`, `/shorten`, `/jobs`, and `/:code` |
| [apps/url-shortener/src/controllers/linkController.js](../../apps/url-shortener/src/controllers/linkController.js) | App request handlers | `POST /shorten` and redirect behavior |
| [modules/load-balancing/README.md](../load-balancing/README.md) | Load balancing lesson | How gateway traffic is distributed across replicas |
| [modules/rate-limiting/README.md](../rate-limiting/README.md) | Rate limiting lesson | A gateway policy built on top of this entry point |

The key Nginx pattern is:

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

location = /api/shorten {
  proxy_pass http://$backend/shorten;
}
```

The shared `proxy_set_header` directives apply to proxied routes in the server.
Each `location` block then stays focused on route mapping. For example, when the
public route `/api/shorten` is called, Nginx forwards it to the internal app
route `/shorten` on `app:3000` while preserving useful client headers.

## Run

Run these commands from the repository root:

```bash
```

The output should end with:

```text
systems-design
```

Start the base stack:

```bash
make base
```

Run the guided API gateway demo:

```bash
./modules/api-gateway/demo.sh
```

The demo pauses between steps. At each step, identify which component answered: the gateway itself or the app behind the gateway.

## How to read the commands

A gateway request has this shape:

```bash
curl -i http://localhost:8080/api/health
```

| Part | Meaning |
|---|---|
| `curl` | send an HTTP request from the terminal |
| `-i` | include response headers, so status and routing behavior are visible |
| `localhost:8080` | the public gateway address on the host |
| `/api/health` | the public gateway path being requested |

A direct app request would look like this:

```bash
curl http://localhost:3000/health
```

That should fail in this lab because the app port is not published on the host. The app is intentionally reachable through the gateway, not directly from the outside.

## How to read the output

The gateway's own health endpoint returns plain text:

```text
gateway ok
```

That proves Nginx itself answered the request.

The public `/api/health` route returns JSON from the app:

```json
{"host":"<container>","role":"app"}
```

That proves the gateway forwarded the request to the app, and the app answered.

A redirect response contains a status and a `Location` header:

```text
HTTP/1.1 302 Found
Location: https://example.com
```

That proves the request went through the gateway to the app, and the app returned an HTTP redirect back through the gateway.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves the gateway forwarded the request because /api/health returned the app container hostname.
```

## What to observe

1. **Gateway health** - `/gateway-health` is answered by Nginx itself. It proves the gateway process is alive.
2. **Route mapping** - `/api/health` goes through the gateway and is answered by the app's internal `/health` route.
3. **Network boundary** - `localhost:3000` is not exposed on the host, so external callers must use the gateway.
4. **Route behavior** - `POST /api/shorten` creates a code, and `GET /api/links/:code` returns a redirect.
5. **Config ownership** - Nginx owns the public forwarding rule with `location` and `proxy_pass`.
6. **Header forwarding** - the gateway preserves client context with headers such as `Host`, `X-Real-IP`, and `X-Forwarded-For`.

## What you learned

- An API gateway is the system's public entry point, not the business application.
- Gateway routes hide internal service layout from clients.
- Headers, logs, timeouts, and policy are edge concerns that affect every downstream service.
- Load balancing can live near the gateway, but it answers a narrower question.

## Practice experiments

After the guided demo, change one thing at a time and predict the effect before running traffic again:

1. **Add a gateway-only route.** Add another exact `location` like `/gateway-version` in the Nginx config, reload Nginx, and confirm the app is not involved.
2. **Change a timeout.** Lower `proxy_read_timeout`, reload Nginx, then compare behavior with a slow app replica from load balancing.
3. **Inspect headers.** Add temporary app logging for request headers, send traffic through the gateway, and identify `X-Forwarded-For`.
4. **Compare with rate limiting.** Study rate limiting after this module and identify which parts are gateway policy rather than app logic.
5. **Draw the boundary.** List three behaviors that belong in the gateway and three that should stay inside the application.

Return experimental config changes before moving on:

```bash
docker compose exec gateway nginx -t
docker compose exec gateway nginx -s reload
make reset
```

## Trade-offs

- **Centralized policy vs bottleneck.** A gateway gives one place to enforce routing, auth, limits, and logging. It also becomes a critical dependency that must be scaled and monitored carefully.
- **Gateway logic vs service logic.** Boundary policy belongs at the gateway; domain behavior belongs in services. Mixing them makes the gateway hard to change and turns it into a large application.
- **One public entry point vs direct service access.** A gateway hides internal services and simplifies clients, but it means clients depend on the gateway being available.
- **TLS termination at the edge.** Managing certificates at the gateway simplifies backend services, but the gateway becomes a trust boundary and must forward only to trusted networks.
- **Version routing vs complexity.** The gateway can route `/v1` and `/v2` to different backends during migrations, but too many routing rules become difficult to reason about.

## Next steps

- [Load balancing](../load-balancing/README.md) for distributing gateway traffic across replicas.
- [Rate limiting](../rate-limiting/README.md) for adding boundary protection.
- [Circuit breakers](../circuit-breakers/README.md) for failure behavior behind the gateway.

## Further reading

- Nginx, "Reverse Proxy": https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/
- Nginx, "Using NGINX as an API Gateway": https://www.nginx.com/blog/deploying-nginx-plus-as-an-api-gateway-part-1/
- Microsoft Azure Architecture Center, "Gateway routing pattern": https://learn.microsoft.com/azure/architecture/patterns/gateway-routing
- Microsoft Azure Architecture Center, "Gateway offloading pattern": https://learn.microsoft.com/azure/architecture/patterns/gateway-offloading

## Cleanup

```bash
make reset
```
