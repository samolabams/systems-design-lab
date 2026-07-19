# Back-Of-The-Envelope Estimation

**Track:** Foundations
**Prerequisites:** none

## Outcome

After this module, you should be able to turn rough product
requirements into QPS, storage, bandwidth, and latency estimates, then use those
numbers to decide whether a cache, queue, replica, or shard is actually needed.
You should also be able to state which assumption would change the design if it
turned out to be wrong.

## What you will build or run

1. A back-of-the-envelope estimate for traffic, storage, throughput, and bandwidth.
2. Unit conversions that turn vague scale into numbers.
3. A capacity check that tells whether a scaling mechanism is justified.
4. A reusable habit for validating design choices with simple math.

## Why this matters

Estimation is how you decide whether you even *need* a cache, a shard, or a
queue - *before* building it. A 60-second calculation often shows that a single
well-tuned database on commodity hardware benchmarked in 2026 comfortably
handles the load, saving you from premature complexity (when not to scale).
Conversely, it can reveal a real ceiling early, before it becomes a production
incident. The skill is producing a defensible number fast.

The output of estimation is not a precise forecast. It is a decision filter. If
the estimate says a design is 100x below a known limit, the simple design is
probably fine. If it says the design is within 2x of a limit, you need a sharper
measurement, a safer architecture, or both.

## Concept

Back-of-the-envelope estimation turns vague requirements into a few numbers that
drive the design:

- **QPS** - queries (requests) per second, along with the read:write ratio: how
  many reads you serve for every write. Most systems read far more than they
  write.
- **Storage** - bytes/record × records, plus growth rate.
- **Bandwidth** - request/response size × QPS: how much network traffic you push.
- **Working set** - the slice of your data that is "hot", meaning it gets read
  often enough to be worth keeping in a cache. Cold data that is rarely touched
  gains nothing from caching.

The trap is **stale constants.** Many guides still use 2010-era numbers; on
modern hardware a single relational database can handle tens of thousands of writes per second
(**TPS**, transactions per second) and tens of TB, and one in-memory cache can do
100k+ ops/s. Using old numbers makes you shard and cache far earlier than reality
requires.

A tiny URL-shortener estimate has this shape:

| Assumption | Quick math | Design signal |
|---|---:|---|
| 10 million new links/day | `10,000,000 / 86,400 ~= 116 writes/sec` | one primary can likely handle writes |
| 100 redirects per new link | `116 * 100 ~= 11,600 reads/sec` | reads dominate; cache may help hot links |
| 500 bytes/link metadata | `10,000,000 * 500 ~= 5 GB/day` | storage growth matters over months |
| 1 KB redirect response | `11,600 KB/sec ~= 12 MB/sec` | bandwidth is manageable in one region |

Those numbers are intentionally rough. Their job is to choose the next question,
not to predict production exactly.

## How it works

This module pairs a worksheet with real measurement so the reader's mental
model is calibrated against *this* machine, not folklore:

- Worksheet - fill in the formulas for the URL-shortener: [estimate.md](estimate.md)
- Measurement - `measure.sh` times the lab's actual cache-less DB read,
  cross-container RTT, and request latency so the estimate can be compared to
  ground truth: [measure.sh](measure.sh)

## Run

```bash
make base
./modules/estimation/demo.sh
./modules/estimation/measure.sh   # cache-less DB read, cross-container RTT, etc.
```

Then compare the numbers in [estimate.md](estimate.md) against the measured values.


## How to read the commands

Read `make base` as starting the smallest complete system. Read
`./modules/estimation/demo.sh` as the guided version of the measurement pass.
Read `measure.sh` as the raw calibration tool: it measures the local lab rather
than relying on generic internet latency tables.

## How to read the output

Treat every number as an order-of-magnitude signal. A result of a few
milliseconds and a result of hundreds of milliseconds imply very different
design choices. Compare measured DB and network latency with the budgets in
[estimate.md](estimate.md), then decide whether the next component is justified.

Read each estimate as a chain: assumption -> formula -> design signal. If the
assumption is uncertain, keep it visible instead of hiding it in a final number.
For example, changing average object size from 500 bytes to 5 KB changes storage
growth by 10x; changing write QPS from 100 to 10,000 changes whether one primary
is still comfortable.

## What to observe

1. The measured single-DB read latency (typically a few milliseconds here) is
   well below a typical request budget (say, a 100 ms target) - so there is lots
   of headroom left before adding a cache is justified.
2. Cross-container RTT (round-trip time - a packet to another container and back)
   is sub-millisecond here; a *cross-region* hop would add 80–150 ms (the multi-region DR
   number). Distance dominates.
3. The estimated QPS ceiling for one relational database (tens of thousands of writes/sec)
   is high enough that sharding - splitting data across many databases (partitioning and sharding) -
   only pays off well past the scale of most applications.

For each estimate, write one sentence in this form:

```text
This number suggests _____ because it is far below/near/above _____.
```

## What you learned

- Estimation turns product requirements into engineering constraints.
- Rough numbers are often enough to reject unnecessary complexity or reveal real bottlenecks.
- Traffic, storage, and bandwidth estimates should use explicit assumptions.
- Scaling decisions are stronger when tied to measured or estimated load.

## Practice experiments

1. Change the assumed read:write ratio in [estimate.md](estimate.md) and note the
   new read QPS.
2. Increase traffic by 10x on paper and identify the first likely bottleneck.
3. Decide whether caching is justified before measuring the base system.

## Trade-offs

- Estimates are for *orders of magnitude*, not precision - round aggressively.
- A tuned single relational database handles tens of thousands of TPS (transactions/sec) and
  tens of TB; a single in-memory cache does 100k+ ops/s; a broker does ~1M msgs/s. Given
  those, sharding rarely pays off until you've exhausted vertical + replica +
  cache (when not to scale).

## Next steps

- [When not to scale](../when-not-to-scale/README.md) for avoiding unsupported complexity.
- [Database scaling](../database-scaling/README.md) for applying estimates to data pressure.
- [The design method](../design-method/README.md) for using estimates in a full design.

## Further reading

- Jeff Dean, "Numbers Everyone Should Know" (the canonical latency table):
  https://colin-scott.github.io/personal_website/research/interactive_latency.html
- Google SRE Workbook - "Implementing SLOs" (turning numbers into targets):
  https://sre.google/workbook/implementing-slos/
- *Designing Data-Intensive Applications*, Ch. 1 (describing load).
  https://dataintensive.net/

## Cleanup

```bash
make reset
```
