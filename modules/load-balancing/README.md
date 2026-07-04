# Load balancing

**Track:** Components
**Prerequisites:** none

> **Status:** Runnable - demonstrates request distribution on the base stack;
> the optional HAProxy contrast runs with `make load-balancing-haproxy`.

## Outcome

After this module, you should understand load balancing as a request-routing
mechanism rather than a generic scaling label. You should be able to explain:

1. What a load balancer does: it receives client traffic and chooses which
   backend instance should handle each request.
2. Why load balancing matters: it improves capacity, availability, and failure
   isolation when a service has multiple replicas.
3. What a backend, replica, upstream, and gateway are.
4. How common strategies such as round-robin, least-connections, and hashing
   make different routing decisions.
5. The difference between L4 and L7 load balancing.
6. The difference between passive and active health checks.
7. Why DNS-level round-robin is not the same thing as a local L4/L7 load
   balancer.

## What you will build or run

1. Multiple app replicas behind the gateway.
2. Repeated requests that show traffic distributed across healthy backends.
3. A health-check or failure scenario that removes an unhealthy backend from rotation.
4. A contrast between gateway routing, DNS, and load-balancer decisions.

Important lab caveat: the base Nginx gateway uses Docker DNS, and short samples
can look pinned because of resolver caching. The module therefore separates two
ideas: the base gateway shows the practical limitation, while the HAProxy
contrast shows explicit backend membership and active health checks more clearly.
When you see uneven Nginx output, treat it as evidence for why service discovery
and active balancing matter, not as a failure of the lesson.

## Why this matters

**Load balancing is the mechanism that spreads client traffic across multiple
copies of a service.** A single application server has limited CPU, memory,
network bandwidth, and process capacity. When every request goes to one server,
that server becomes both a bottleneck and a single point of failure. Adding more
servers only helps if something decides how traffic should be distributed across
them.

A load balancer sits in front of a group of service instances. Clients send
requests to one stable address, and the load balancer forwards each request to
one backend instance. This gives the system one public entry point while letting
the application run as several private copies behind it.

Load balancing affects several production outcomes:

- **Capacity** — more replicas can serve more total traffic than one replica.
- **Availability** — if one replica fails, traffic can continue flowing to the
  remaining healthy replicas.
- **Latency** — a good strategy avoids sending too much work to an already busy
  replica.
- **Deployability** — replicas can be added, removed, or replaced while the
  frontend address stays stable.

The concept is independent of any one proxy or load-balancing product. The lab
uses a local gateway and several app replicas as one concrete implementation so
service discovery, traffic distribution, slow-node behavior, sticky routing, and
the difference between passive and active failure detection are visible.

## Concept

Load balancing begins with a simple request path:

```text
client -> load balancer -> one backend replica
```

The client does not choose a replica directly. The client talks to the load
balancer. The load balancer chooses a backend, forwards the request, receives the
response, and sends that response back to the client.

The main vocabulary:

- **Client** — the caller making the request, such as a browser, mobile app, or
  another backend service.
- **Load balancer** — the component that receives incoming traffic and forwards
  each request or connection to a backend.
- **Backend** — a service instance that can actually handle the request.
- **Replica** — one copy of the same backend service. Three replicas means three
  running copies of the same app.
- **Upstream** — the set of backend replicas a proxy can send traffic to. Nginx
  and HAProxy both use this word.
- **Gateway** — the front door of the system. In this lab, the gateway is the
  Nginx container that receives traffic on `localhost:8080` and forwards it to
  app replicas.

Load balancing has two core jobs:

1. **Distribute traffic.** For each request or connection, choose which backend
   should receive it.
2. **Avoid unhealthy backends.** Detect replicas that are failing or too slow and
   stop sending traffic to them.

The selection rule is called a **balancing strategy**.

| Strategy | How it chooses | When it helps | Main limitation |
|---|---|---|---|
| **Round-robin** | send each request to the next backend in order | replicas are similar and requests take similar time | ignores current load and backend speed |
| **Weighted round-robin** | send more requests to backends with higher weights | some replicas are larger than others | weights must be chosen and updated correctly |
| **Least-connections** | send to the backend with the fewest active requests | request durations vary | requires tracking live connection counts |
| **Least-response-time** | send to the backend responding fastest | latency is the main signal | can be noisy and requires measurement |
| **Hash-based routing** | hash a stable value, such as client IP or URL | the same client/key should return to the same backend | can create uneven load |

Round-robin and weighted round-robin are mostly **static** strategies: they do
not need much live state. Least-connections, least-response-time, and some
health-aware strategies are **dynamic**: they react to live conditions, but the
load balancer must measure and track more information.

## L4 and L7 load balancing

Load balancers can operate at different layers of the network stack:

- **L4 (transport layer)** — balances TCP or UDP connections using information
  such as IP address and port. It does not inspect the HTTP path, headers, or
  cookies. L4 balancing is fast and simple, but it has less routing context.
- **L7 (application layer)** — understands the application protocol, such as
  HTTP. It can route based on paths, headers, cookies, or methods. L7 balancing
  gives more control, but it does more work per request.

In this lab, Nginx and HAProxy are the concrete HTTP-aware L7 balancers. They
receive HTTP requests and forward them to app replicas.

## Health checks

A load balancer should avoid sending traffic to a backend that cannot serve it.
There are two common ways to learn that a backend is unhealthy:

- **Passive health detection** — infer failure from real user requests. If a
  backend times out or returns connection errors several times, the balancer
  temporarily avoids it. This is simpler, but some users experience the first
  failures.
- **Active health checks** — probe backends in the background, often by calling a
  path such as `/health`. If a probe fails repeatedly, the balancer removes that
  backend before normal user traffic reaches it.

Open Source Nginx primarily gives passive failure detection for this kind of
setup. HAProxy includes active health checks in its open-source version, so the
lab uses HAProxy as a contrast implementation.

## DNS vs load balancing

DNS covers DNS and name resolution, including the idea that one DNS name can
return multiple A records. That can spread clients across addresses, but it is
not the same as a local L4/L7 load balancer.

DNS answers the question, "what address or record belongs to this name?" A load
balancer answers a different operational question: "which healthy backend should
handle this request right now?"

DNS-level round-robin is blunt because clients and resolvers cache answers, DNS
does not inspect HTTP requests, and DNS alone does not reliably know whether a
backend is healthy. A local L4/L7 balancer sits on the request path and can make
per-request or per-connection decisions.

## How it works

The base profile starts a gateway and an application service:

```text
client curl -> gateway (Nginx) -> app replicas
```

The app can be scaled to several replicas with Docker Compose. Each replica runs
the same application code and exposes the same `/health` endpoint. The gateway
receives requests on the host and forwards them to one of the app replicas on
the internal Docker network.

The important files are:

| File | Role in the lab | What to inspect |
|---|---|---|
| [infra/gateway/nginx/nginx.conf](../../infra/gateway/nginx/nginx.conf) | Active Nginx gateway config | `resolver 127.0.0.11`, `proxy_pass`, timeout settings, and passive failover settings |
| [infra/gateway/nginx/variants/round-robin.conf](../../infra/gateway/nginx/variants/round-robin.conf) | Explicit round-robin variant | Static `upstream` block syntax |
| [infra/gateway/nginx/variants/least_conn.conf](../../infra/gateway/nginx/variants/least_conn.conf) | Least-connections variant | `least_conn` directive |
| [infra/gateway/nginx/variants/ip_hash.conf](../../infra/gateway/nginx/variants/ip_hash.conf) | Sticky routing variant | `ip_hash` directive |
| [infra/gateway/haproxy/haproxy.cfg](../../infra/gateway/haproxy/haproxy.cfg) | HAProxy contrast config | `balance roundrobin`, `option httpchk`, `server-template`, and the stats listener |

The base Nginx config uses Docker's embedded DNS resolver at `127.0.0.11`. The
line `set $backend "app:3000"` plus `proxy_pass http://$backend` makes Nginx use
the Docker service name rather than a hard-coded container IP. That is useful
service discovery plumbing, but it is not a perfect rapid round-robin demo:
Docker DNS and Nginx resolver caching can make several quick requests stay pinned
to the same replica.

There are two important caveats, and both are part of the lesson:

1. The base Nginx path can appear pinned during short tests because DNS answers
   are cached.
2. Open Source Nginx resolves a static upstream such as
   `upstream { server app:3000; }` only once at startup. Under Docker `--scale`,
   that can pin Nginx to one replica IP.

The module keeps these caveats visible because they explain why dedicated load
balancers and dynamic service discovery become important. HAProxy is included as
the cleaner contrast: it uses `server-template` to track backend membership and
`option httpchk` to actively probe backend health.

## Run

Run these commands from the repository root:

```bash
pwd
```

The output should end with:

```text
systems-design
```

Start the base stack:

```bash
make base
```

Run the guided load balancing demo:

```bash
./modules/load-balancing/demo.sh
```

The demo pauses between steps. For each step, read the command before looking at
the output. The goal is to connect each output to one load balancing idea:
replicas, distribution, slow-node behavior, strategy choice, or health checking.

The guided demo starts the HAProxy contrast when it reaches the active-check
section. To inspect HAProxy manually after the demo, start the profile yourself:

```bash
make load-balancing-haproxy
```

Then open the HAProxy stats page:

```text
http://localhost:8404/stats
```

## How to read the commands

Scaling the app:

```bash
docker compose up -d --scale app=3 --no-recreate
```

| Part | Meaning |
|---|---|
| `docker compose up -d` | ensure containers are running in the background |
| `--scale app=3` | run three replicas of the `app` service |
| `--no-recreate` | keep existing containers when possible |

Sending traffic through the gateway:

```bash
curl -s http://localhost:8080/health
```

| Part | Meaning |
|---|---|
| `curl` | send an HTTP request from the terminal |
| `-s` | quiet mode; hide progress output |
| `http://localhost:8080` | the Nginx gateway exposed on the host |
| `/health` | the app endpoint used to prove which replica answered |

Inspecting service discovery inside the Docker network:

```bash
docker compose exec gateway getent hosts app
```

This asks the `gateway` container to resolve the service name `app`. If several
replicas exist, several IP addresses should appear.

## How to read the output

The `/health` response includes the identity of the app replica that handled the
request. When traffic is distributed, repeated responses show different
hostnames:

```text
{"ok":true,"host":"systems-design-app-2"}
{"ok":true,"host":"systems-design-app-1"}
{"ok":true,"host":"systems-design-app-3"}
```

The exact container names may differ. If more than one host appears, traffic is
being distributed across replicas. If one host repeats during a short Nginx test,
that is also useful evidence: it shows how DNS/resolver caching can pin a simple
gateway path to one backend for a period of time.

The timing command prints request duration:

```bash
curl -s -o /dev/null -w '%{time_total}s ' http://localhost:8080/health
```

Values near `0.750s` indicate the intentionally slow replica. If round-robin is
used, the slow replica still receives its share of requests, so some requests
are much slower than others.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves traffic is distributed because different app hostnames answer repeated requests.
```

## What to observe

1. **Replicas** — after scaling, there are multiple running copies of the same
   `app` service.
2. **Service discovery** — inside the gateway, `getent hosts app` resolves the
   service name `app` to a backend IP. Repeating it may show how DNS answers are
   cached or rotated.
3. **Base Nginx path** — repeated requests to `/health` may show more than one
   backend hostname, or they may repeat one hostname while DNS is cached. Both
   outcomes are part of the lesson.
4. **HAProxy distribution** — requests through `localhost:8082` provide the
   clearer pure-balancer contrast because HAProxy tracks app backends explicitly.
5. **Slow-node behavior** — an intentionally slow replica causes timing spikes
   only when the gateway sends traffic to it. If no spike appears, the gateway
   stayed pinned elsewhere during that sample.
6. **Strategy syntax** — `least_conn` and `ip_hash` load as Nginx directives, but
   the Docker `--scale` caveat explains why static upstreams are not enough for
   dynamic replica membership.
7. **Passive failure detection** — killing a replica behind Nginx can cause some
   failed requests before Nginx routes around it.
8. **Active health checks** — HAProxy probes `/health` and shows backend status
   on the stats page.

## What you learned

- Load balancing spreads requests across replicas to improve capacity and resilience.
- Health checks decide which replicas should receive traffic.
- L4 and L7 load balancers operate with different information.
- Load balancing helps stateless services most; shared state can still bottleneck the system.

## Practice experiments

After the guided demo, change one thing at a time and predict the effect before
running traffic again:

1. **Change replica count.** Scale to two replicas, then four replicas, and
   observe how many hostnames appear in repeated `/health` responses.
2. **Increase the sample size.** Send 30 requests instead of 9 and count how
   often each hostname appears.
3. **Remove a replica.** Stop one app container and observe whether requests
   fail before the gateway routes around it.
4. **Compare HAProxy.** Start `make load-balancing-haproxy`, open the stats
   page, and watch backend health while stopping a replica.
5. **Read the config.** Open the active Nginx config and identify the line that
   forwards traffic to `app:3000`.

Return the stack to a clean state before moving on:

```bash
make reset
make base
```

## Trade-offs

- **Round-robin vs least-connections.** Round-robin is simple and predictable,
  but it assumes requests and backends are similar. Least-connections reacts
  better when some requests last longer, but it requires live connection state.
- **Sticky routing vs even balance.** `ip_hash` can keep the same client on the
  same backend, which helps when state is stored in memory. It can also overload
  one backend if many requests hash to the same place. Prefer stateless app
  replicas plus shared state when possible.
- **Passive vs active health checks.** Passive detection is simpler, but real
  user traffic sees the first failures. Active checks cost background probes,
  but they can remove bad backends before users hit them.
- **L4 vs L7.** L4 balancing is fast and protocol-agnostic. L7 balancing can use
  HTTP paths, headers, and cookies, but it does more work and becomes a stronger
  policy point in the system.
- **Global vs local balancing.** This module shows local balancing: one balancer
  spreads traffic across servers in one cluster or data center. Global traffic
  steering, often implemented with DNS or GSLB, is a separate concern and belongs
  with DNS/multi-region DR context.
- **TLS termination.** An L7 balancer can decrypt HTTPS at the front door so
  backends receive plain HTTP and do not each spend CPU on decryption. This
  centralizes certificates, but it also makes the balancer a trust boundary.

## Next steps

- [Scaling](../scaling/README.md) for vertical and horizontal growth.
- [Service discovery](../service-discovery/README.md) for finding changing backends.
- [API gateway](../api-gateway/README.md) for the public edge path.

## Further reading

- Nginx, "HTTP Load Balancing": https://nginx.org/en/docs/http/load_balancing.html
- HAProxy, "Health checking" (active checks): https://docs.haproxy.org/2.9/configuration.html#5.2
- Docker, "Networking and embedded DNS": https://docs.docker.com/engine/network/

## Cleanup

```bash
# the demo backs up nginx.conf and restores it automatically on exit;
# if you interrupted it mid-run, restore the default by hand:
cp infra/gateway/nginx/nginx.conf.orig infra/gateway/nginx/nginx.conf 2>/dev/null || true
make reset
```
