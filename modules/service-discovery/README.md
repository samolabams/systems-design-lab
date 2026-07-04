# Service discovery

**Track:** Components
**Prerequisites:** none

> **Status:** Runnable - Consul registers three app replicas with HTTP health
> checks; stopping one instance removes it from the healthy set.

## Outcome

After this module, you should understand service discovery as
dynamic membership plus health-based routing. You should be able to explain
service registration, health checks, registries, DNS/API discovery, and why
static gateway upstreams do not work well with autoscaling.

## What you will build or run

1. A service lookup scenario where callers use names instead of fixed container addresses.
2. Commands that show how services find each other on the Docker network.
3. A changing-backend scenario that explains why discovery matters when replicas move.
4. A contrast between DNS-style discovery and gateway routing.

## Why this matters

In load balancing the gateway used a static `upstream` list, and Open Source Nginx resolved
it once at boot. That configuration cannot track instances that appear and
disappear during autoscaling, deployments, or failures. Autoscaling means
automatic adjustment of replica count in response to load or policy. Real
systems need a **registry**: services register themselves, report health, and the
load balancer routes only to **healthy** entries. This is the active health
checking and dynamic membership that load balancing's static configuration lacked.

## Concept

- **Service registry** — a source of truth (Consul/etcd/ZooKeeper) of "what
  instances of service X exist and are healthy right now."
- **Registration** — instances register on start and deregister on stop; a **TTL**
  (Time To Live — a lease that must be renewed, and expires if not) or health
  check evicts ones that crash.
- **Passing instance** — an instance whose latest health check succeeded. Consul
  returns only these instances when the query asks for healthy, routable service
  members.
- **Health-based routing** — the balancer (or a sidecar) pulls healthy endpoints
  from the registry and routes only to those — an **active** check (the system
  probes each instance on a schedule), vs load balancing's **passive** approach (wait for a
  request to fail, then eject after N errors).
- **Client-side vs server-side discovery** — the client queries the registry and
  picks an instance, or a load balancer does it on the client's behalf.

## How it works

The profile adds a single-node **Consul** (`-dev` mode) — the registry load balancing's static
Nginx upstream lacked. The demo (`demo.sh`):

1. Scales the app tier to **3 replicas** behind the one `app` service name.
2. **Registers** each replica in Consul as service `app`, each with an HTTP health
   check that polls `GET /health` every 3s.
3. Queries Consul for the **passing** instances — the source of truth a
   discovery-aware balancer would route from (no Nginx edit required).
4. **Stops one replica.** Its health check starts failing, and within a few
  intervals Consul removes it from the healthy set. This demonstrates the
  active health checking and dynamic membership that load balancing could not provide.

The registration is done explicitly from the demo (rather than a sidecar) so the
register → health-check → evict lifecycle is visible in plain `consul` API calls.
Wiring Consul back into the gateway (consul-template regenerating the upstream) is
the production step this leaves as the obvious extension.

The demo uses the Consul HTTP API endpoint
`/v1/health/service/app?passing`. Read that as: "return registered `app`
instances whose latest health check is passing." The `?passing` filter matters
because a registry may know about an instance that exists but is not healthy
enough to route traffic to.

Each registered instance includes a health-check policy:

| Field | Meaning in the demo |
|---|---|
| `http` | Consul calls the replica's `/health` endpoint. |
| `interval: 3s` | Consul checks every three seconds. |
| `timeout: 2s` | A check fails if the endpoint does not answer within two seconds. |
| `deregister_critical_service_after: 30s` | A long-failing instance is removed from the catalog. |

Those values create the timing you observe after a container stops: the passing
set changes only after one or more scheduled checks notice the failure.

## Run

```bash
pwd
make service-discovery
./modules/service-discovery/demo.sh
```

Run non-interactively with `AUTO=1 ./modules/service-discovery/demo.sh`.

The output of `pwd` should end with `systems-design`.

## How to read the commands

Read the Consul API commands as registry operations: register an instance, ask
which instances are healthy, then observe what changes after one instance stops.
The app containers are the service instances; Consul is the source of dynamic
membership.

## How to read the output

A service instance listed as `passing` is eligible for routing. An instance that
disappears from the passing set after it is stopped has been removed by active
health checking. The important comparison is with load balancing: no gateway config edit is
needed for the registry to know membership changed.

## What to observe

1. All three replicas register and show up as **passing** in Consul with no config
   edit — the registry discovered them.
2. A stopped instance fails its health check and is removed from the passing set
   within a couple of check intervals — discovery never returns a dead instance.
3. Contrast with load balancing: the static `upstream` resolved once at boot and could only
   detect failure passively, after serving errors.

## What you learned

- Service discovery lets callers find service instances without hard-coded addresses.
- Dynamic systems need a lookup mechanism because instances start, stop, and move.
- Discovery and load balancing are related but not identical.
- Internal names are part of the system contract between services.

## Practice experiments

1. Change the health-check interval on paper and predict the failure-detection
  delay.
2. Explain whether a client or a load balancer should query the registry in this
  lab.
3. Sketch how consul-template could regenerate the gateway upstream from healthy
  instances.

## Trade-offs

- **The registry is critical infrastructure** — it must itself be HA (it usually
  runs on consensus; see leader election for election/quorum behavior); if it is down,
  discovery is down as well.
- **Staleness window** — health checks have an interval; there's always a short gap
  between failure and eviction.
- **Added complexity** — agents/sidecars, health endpoints, and registration logic
  are more moving parts than a static list.
- **Thundering reconnects** — a flapping instance can churn the routing table; damp
  it with stabilisation windows.

## Next steps

- [DNS](../dns/README.md) for name resolution foundations.
- [Load balancing](../load-balancing/README.md) for choosing among healthy replicas.
- [API gateway](../api-gateway/README.md) for public entry points.

## Further reading

- HashiCorp, "Consul — Service Discovery":
  https://developer.hashicorp.com/consul/docs/concepts/service-discovery
- Chris Richardson, "Service Discovery in a Microservices Architecture":
  https://www.nginx.com/blog/service-discovery-in-a-microservices-architecture/
- "etcd" docs: https://etcd.io/docs/

## Cleanup

```bash
make reset
```
