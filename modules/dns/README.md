# DNS & name resolution

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand DNS as a name-resolution mechanism
rather than a hidden internet detail. You should be able to explain:

1. What DNS does: it turns a name such as `www.example.com` into information a
  client can use, usually an IP address.
2. What a domain name, zone, and fully qualified domain name are.
3. Why DNS is hierarchical: one server does not know every name, so the lookup is
  delegated from a broader zone to a more specific zone.
4. What a resolver does: it accepts the client's question, finds or fetches the
  answer, and caches it for a limited time.
5. What an authoritative server does: it owns the zone data and returns the real
  records for that zone.
6. How to read a `dig` response: identify the server asked, the record type, the
  answer section, the authoritative flag, and the TTL.
7. Why DNS changes are not instant: cached answers remain valid until their TTL
  expires.

## What you will build or run

1. A local DNS lab with root, authoritative, and resolver roles.
2. Queries that show name resolution step by step.
3. Record changes that make TTL and caching behavior visible.
4. A connection between DNS names and service entry points.

## Why this matters

**DNS is the naming system that maps a human-readable name to the network
address clients actually use.** People remember names such as `example.com`,
`api.company.com`, or `mail.company.com`; networks deliver packets to addresses
such as `93.184.216.34` or `2606:2800:220:1:248:1893:25c8:1946`. DNS is the
system that connects those two worlds. Before a browser, mobile app, backend
service, or database client can connect to another system by name, that name
must be resolved.

DNS is part of the critical path of almost every network request. If DNS is
wrong, the application may be healthy but unreachable. If DNS is cached, a
recent change may not be visible everywhere yet. If DNS returns several possible
addresses, different clients may reach different backends. Misconfigured DNS in
production often appears as a deployment that works for only some users, a
failover that is ignored because resolvers cached the old address, or a service
that cannot be reached even though it is running.

The concept is independent of any one DNS server. The lab uses a small local DNS
environment as one concrete implementation so resolution, record types,
delegation, and TTL-based staleness are visible.

DNS does not create the network connection by itself. It answers a naming
question. After DNS returns an address, the client still has to open a TCP, UDP,
or QUIC connection to the destination and speak the application protocol, such
as HTTP or PostgreSQL. Keeping that boundary clear prevents a common confusion:
DNS tells a client where to go; it does not send the application request there.

## Concept

DNS is a **distributed, hierarchical directory** for names. It is distributed
because no single server stores every DNS name in the world. It is hierarchical
because names are organized from broad to specific parts, such as:

```text
.
com.
example.com.
www.example.com.
```

The dot at the top represents the DNS root. Below it are top-level domains such
as `com`, `org`, or `net`. Below those are domains such as `example.com`. Below
those are hostnames or service names such as `www.example.com` or
`api.example.com`.

Three vocabulary terms appear throughout DNS documentation:

- **Domain name** — a name in the DNS hierarchy, such as `example.com` or
  `www.example.com`.
- **Fully qualified domain name (FQDN)** — the complete name from a host all the
  way up to the root. DNS tools often show this with a trailing dot, such as
  `www.example.com.`. The final dot means "this name is complete; do not append
  anything else."
- **Zone** — the portion of the DNS namespace managed by one authority. For
  example, `example.com` can be a zone, and that zone can contain records for
  `www.example.com`, `api.example.com`, and `mail.example.com`.

A DNS lookup walks through that hierarchy until it reaches a server that is
allowed to answer for the requested name. The work is split across tiers:

- **Root** — the top of the DNS hierarchy. It does not know every application's
  address; it knows where to send the next question for broad zones and returns
  a **referral** ("ask that server").
- **Authoritative name server** — the tier that actually *owns* a zone and gives
  real answers for names in that zone. Authoritative answers are marked with the
  **authoritative answer** flag (`aa`).
- **Resolver** — the server a client talks to, such as an operating-system or
  ISP resolver. A true **recursive** resolver walks the hierarchy on behalf of
  the client and returns the final answer.

In plain terms, a lookup is a question-and-answer path:

```text
client asks: "where is www.example.com?"
resolver asks whatever server can answer
authoritative server returns the record
resolver gives the client the final answer
```

The important point is that DNS answers are not only IP addresses. DNS can also
answer questions such as "which server receives mail for this domain?", "is this
name an alias?", and "which server is allowed to speak for this zone?".

In this lab, the general DNS roles are represented by local containers:
`dns-root` acts like the root tier for the lab domain, `dns-auth` is
authoritative for `shop.internal.`, and `dns-resolver` is the resolver that the
client queries.

The data itself lives in **resource records (RRs)**, each binding a name to a
type and a value. The zone this module serves shows the everyday types:

| Type | Answers the question | Example in this zone |
|---|---|---|
| **A** | what IPv4 address is this name? | `www` → `10.0.0.11`, `10.0.0.12` |
| **AAAA** | what IPv6 address? | `www` → `2001:db8::11` |
| **CNAME** | this name is an *alias* for which other name? | `api` → `www.shop.internal.` |
| **MX** | where does mail for this domain go? | `@` → `mail.shop.internal.` (priority 10) |
| **TXT** | arbitrary text (verification, SPF, DMARC) | `@` → `"v=spf1 …"` |
| **SRV** | where does a named *service* live (host + port)? | `_http._tcp` → `www:80` |
| **NS** | which servers are authoritative for this zone? | `@` → `ns1.shop.internal.` |
| **SOA** | the zone's "birth certificate": serial, timers, default TTL | one per zone |

Two ideas make the whole system fast and scalable rather than a single
bottleneck for the entire internet:

- **Recursive vs iterative.** In an **iterative** lookup the *client* does the
  legwork: ask the root, get a referral, then ask the server it named. In a
  **recursive** lookup the client asks its resolver once and the *resolver* does
  that walk and returns the final answer. Recursion is friendlier to clients;
  iteration keeps the upstream servers stateless (they answer one step and
  forget the client), which is why the root and TLD tiers work iteratively.
- **Caching & TTL.** Every record carries a **TTL** (time-to-live) — how many
  seconds a resolver may reuse the answer before asking again. Caching at the
  browser, OS, and resolver is what keeps DNS from melting under internet-scale
  load, but it is also why changes are not instant: until the TTL expires, the
  world keeps serving the old value. This is DNS's deliberate trade — it gives up
  strong consistency for speed and settles for **eventual consistency** (consistency models).

## How it works

The profile starts four containers on a private network, `dnsnet`, with **static
IPs** so the delegation "glue" can name fixed addresses:

- `dns-root` (`172.30.53.2`) — authoritative for the root zone `.`, which
  contains nothing but a delegation of `shop.internal.` to the server below. Ask
  it about a `shop.internal.` name and it returns a *referral*, not an answer.
- `dns-auth` (`172.30.53.3`) — authoritative for `shop.internal.`, serving the
  record table above. Its `loadbalance` plugin can rotate the order of `www`'s
  two A records across repeated replies — DNS-level load balancing in action
  (load balancing).
- `dns-resolver` (`172.30.53.4`) — a caching resolver. CoreDNS has no built-in
  recursor, so it *forwards* to the authoritative server; the point is
  identical — the client asks once, the resolver answers and **caches**, and a
  repeat query comes back with a TTL that has counted down.
- `dns-tools` (`172.30.53.5`) — a [netshoot](https://github.com/nicolaka/netshoot)
  container with `dig`, so every query runs from inside the network.

This lab uses **CoreDNS**, a small DNS server that is configured by plugins. A
CoreDNS configuration file is called a **Corefile**. Each block says which DNS
zone the server handles and which plugins should run for queries in that zone.
The DNS data itself lives in **zone files**, which contain records such as `A`,
`CNAME`, `MX`, `NS`, and `SOA`.

The structure is:

```text
Corefile       -> tells CoreDNS how this server behaves
zone file      -> contains the DNS records this server serves
dig command    -> asks a DNS server a question and prints the answer
```

When reading this module, keep those three layers separate. If the behavior is
confusing, first check the Corefile. If the returned data is confusing, check the
zone file. If the terminal output is confusing, check which server and record
type the `dig` command asked for.

The DNS files live in [infra/dns/](../../infra/dns/):

| File | Role in the lab | What to inspect |
|---|---|---|
| [Corefile.root](../../infra/dns/Corefile.root) | Configures `dns-root` as the root-like server for `.` | The `file` plugin points at `db.root` |
| [db.root](../../infra/dns/db.root) | Root zone data | The `NS` delegation and glue `A` record for `shop.internal.` |
| [Corefile.auth](../../infra/dns/Corefile.auth) | Configures `dns-auth` as authoritative for `shop.internal` | The `file` plugin serves the zone; `loadbalance` can rotate A-record order |
| [db.shop.internal](../../infra/dns/db.shop.internal) | Authoritative zone data | The actual records queried by the demo |
| [Corefile.resolver](../../infra/dns/Corefile.resolver) | Configures `dns-resolver` as the client-facing resolver | The `forward` plugin sends queries upstream; `cache 30` makes TTL countdown visible |

Read the Corefile first to learn how the server behaves, then read the matching
zone file to see the records it serves. For example, `Corefile.auth` explains
that `dns-auth` serves `shop.internal`, and `db.shop.internal` contains the
records for `www`, `api`, `mail`, and the other names in that zone.

The resolver is also published on the host at `localhost:${DNS_RESOLVER_PORT:-5354}`
so it can be queried directly with `dig` (on macOS/Colima use `+tcp` —
host→container UDP forwarding is unreliable there; DNS falls back to TCP
normally, so this is only a quirk of querying from the host).

## Run

Run these commands from the repository root:

```bash
pwd
```

The output should end with:

```text
systems-design
```

Start the DNS containers:

```bash
make dns
```

Then run the guided demo:

```bash
./modules/dns/demo.sh          # interactive walk: predict, query, explain
```

The demo pauses between steps. At each step, first read the question, then read
the command, then inspect the output. The goal is not to memorize `dig`; the
goal is to connect each command to one DNS idea.

## How to read the commands

Most commands in this module have this shape:

```bash
docker compose exec dns-tools dig +noall +answer @dns-auth www.shop.internal A
```

Read it from left to right:

| Part | Meaning |
|---|---|
| `docker compose exec dns-tools` | run the command inside the `dns-tools` container |
| `dig` | the DNS lookup tool |
| `+noall +answer` | hide most output and show only the answer section |
| `@dns-auth` | ask the DNS server named `dns-auth` |
| `www.shop.internal` | the DNS name being queried |
| `A` | the record type being requested; here, IPv4 addresses |

Changing one part changes the question. For example, `@dns-root` asks the root
server, `@dns-resolver` asks the resolver, and `MX` asks for mail-routing
records instead of IPv4 addresses.

## How to read the output

An answer line such as this:

```text
www.shop.internal.      30      IN      A       10.0.0.11
```

means:

| Field | Meaning |
|---|---|
| `www.shop.internal.` | the name that was answered |
| `30` | TTL in seconds; a resolver may cache this answer for up to 30 seconds |
| `IN` | internet DNS class; most normal DNS records use this |
| `A` | record type |
| `10.0.0.11` | the value returned for that record |

When the output includes flags, look for `aa`:

```text
;; flags: qr aa rd; QUERY: 1, ANSWER: 2, AUTHORITY: 1, ADDITIONAL: 1
```

The `aa` flag means **authoritative answer**. The server is not merely repeating
something it cached; it is the server responsible for that zone.

If a name does not exist, `dig` shows a response code instead of an answer. For
example, a missing name commonly returns `NXDOMAIN`, which means the DNS server
is saying the requested name does not exist in that zone:

```text
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 12345
```

That is different from an application error. `NXDOMAIN` means the name could not
be resolved; it does not mean the web server, API, or database returned an error.

A few manual queries through the tools container:

```bash
# authoritative answer for the A records (note the two IPs)
docker compose exec dns-tools dig +noall +answer @dns-auth www.shop.internal A

# the root only returns a referral (look in the AUTHORITY section)
docker compose exec dns-tools dig @dns-root www.shop.internal A

# resolve through the caching resolver, from the host
# (on macOS/Colima add +tcp — host→container UDP port forwarding is unreliable there)
dig -p 5354 @127.0.0.1 +tcp www.shop.internal A
```

## What to observe

1. **Hierarchy / referral** — `dig @dns-root www.shop.internal` answers with no
   address, but an AUTHORITY section pointing at `ns1.shop.internal.` plus its
   glue A record. The root refers; it does not resolve.
2. **Authoritative answer** — the same query against `@dns-auth` returns the
   real A records with the `aa` flag set.
3. **Every record type** — walk A, AAAA, CNAME, MX, TXT, SRV, NS, SOA and see
   how each answers a different question about the one domain.
4. **CNAME chase** — `dig @dns-auth api.shop.internal` returns the CNAME *and*
  the target's A records, because the resolver follows the alias.
5. **Round-robin** — repeat the `www` A query and observe both IPs returned; the
  answer order may rotate across queries (the `loadbalance` plugin) — this is
  DNS spreading load (load balancing).
6. **Caching & TTL** — query `@dns-resolver` twice in a row: the first answer
   carries the full TTL (30), the second shows a *lower* number — proof it came
   from cache and is ageing toward a refresh.
7. **Missing name** — query `missing.shop.internal` and observe the response
  code. A DNS failure happens before any application connection can be made.

For each observation, write one sentence in this form:

```text
This output proves _____ because _____.
```

Example:

```text
This output proves dns-auth is authoritative because the flags include aa.
```

## What you learned

- DNS maps names to records through a hierarchy of resolvers and authoritative servers.
- TTL controls how long answers may be cached before another lookup is needed.
- DNS is part of the request path even when application code never calls it directly.
- Name resolution choices affect failover, routing, and operational debugging.

## Practice experiments

After the guided demo, make one change at a time and predict the effect before
running `dig` again:

1. **Add a name.** In [infra/dns/db.shop.internal](../../infra/dns/db.shop.internal),
   add `api2 IN A 10.0.0.30`, restart `dns-auth`, then query
   `api2.shop.internal`.
2. **Change a TTL.** Lower the zone TTL from `30` to `10`, restart `dns-auth`
   and `dns-resolver`, then query `mail.shop.internal` twice through
   `@dns-resolver`. The countdown should shrink faster.
3. **Change an alias.** Point `cdn` at a different target, restart `dns-auth`,
   and compare the CNAME answer with the `api` answer.
4. **Break a lookup deliberately.** Query a name that does not exist, such as
   `missing.shop.internal`, and identify the response code. Then add the record
   and confirm the response changes.

Return each experiment to its original state before moving to another module, or
use the changes as a local scratchpad and reset them deliberately later.

## Trade-offs

- **Freshness vs load (TTL).** A long TTL means fewer queries and faster clients,
  but slow propagation — a failover or IP change can take the full TTL to reach
  everyone. A short TTL propagates quickly but pushes far more traffic at your
  name servers. Operationally, teams *lower* the TTL days before a planned
  migration, then raise it again afterward.
- **Recursive vs iterative.** Recursion is convenient for clients but forces the
  resolver to hold state and do the walking; iteration keeps the root/TLD tiers
  stateless and low-cost, which allows them to serve the internet at large scale.
- **DNS load balancing is blunt.** Handing back multiple A records spreads load
  with little coordination, but DNS cannot see server health, cannot guarantee an even split
  (clients and caches pick arbitrarily), and reacts slowly to failure because of
  caching. That is why real systems put a proper L4/L7 balancer (load balancing) *behind* the
  name — and why global traffic steering (GSLB) needs more than round-robin DNS.
- **Eventual consistency is baked in.** DNS chooses availability and speed over a
  single consistent view; a record update is *lazily* propagated as caches
  expire. Design around it rather than fighting it.

## Next steps

- [Load balancing](../load-balancing/README.md) for traffic distribution after name resolution.
- [Service discovery](../service-discovery/README.md) for internal service lookup.
- [Multi-region, DR and backups](../multi-region-dr/README.md) for failover thinking.

## Further reading

- CoreDNS, "file plugin" (zone files & record types): https://coredns.io/plugins/file/
- CoreDNS, "Setups" (authoritative, forwarding, caching): https://coredns.io/manual/toc/
- RFC 1035, "Domain Names — Implementation and Specification": https://www.rfc-editor.org/rfc/rfc1035

## Cleanup

```bash
docker compose --profile dns down
```
