# Availability & Reliability Math

**Track:** Foundations
**Prerequisites:** none

## Outcome

After this module, you should be able to calculate downtime from
availability targets, distinguish SLI, SLO, and SLA, explain error budgets, and
read reliability signals from the observability dashboard. You should be able
to look at an availability target and say what it costs in allowed failure time,
what must be measured, and which alerts should page a human.

## What you will build or run

1. A small availability model that turns uptime percentages into expected downtime.
2. Calculations for serial and redundant dependencies.
3. Examples that show why one weak dependency can dominate user-visible reliability.
4. A vocabulary bridge between reliability math and design trade-offs.

## Why this matters

"Highly available" is meaningless without a number. The difference between
99.9% and 99.99% is the difference between ~9 hours and ~1 hour of downtime a
year - and roughly an order of magnitude more engineering cost. This module
gives the arithmetic for setting an affordable *target* and measuring whether the
system is meeting it, so reliability becomes a managed number rather than a
guess.

The key habit is to translate adjectives into budgets. "Reliable" becomes a
success ratio over a window. "Too slow" becomes a latency percentile. "Urgent"
becomes a burn rate that says the service is spending its error budget too fast.
That translation is what lets teams distinguish a scary graph from a user-impacting
incident.

## Concept

### The nines

| Availability | Downtime/year | Downtime/day |
|---|---|---|
| 99% (two nines) | ~3.65 days | ~14.4 min |
| 99.9% | ~8.77 hours | ~1.44 min |
| 99.99% | ~52.6 min | ~8.6 s |
| 99.999% | ~5.26 min | ~0.86 s |

### Series vs parallel

- **In series** (a request needs A *and* B): availabilities **multiply**.
  `0.99 × 0.99 = 0.9801` - every added dependency lowers availability.
- **In parallel** (redundant replicas, need *any* one): failure probabilities
  multiply. `1 − (0.01 × 0.01) = 0.9999` - redundancy produces extra nines
  (each digit of "9" is a tenfold cut in downtime). This is why scaling
  (extra app replicas) and replication and failover (a standby database) exist.

### SLI / SLO / SLA + error budgets

- **SLI** - a measured signal, such as success rate or p95 latency. p95 latency
  is the 95th percentile: 95% of requests completed at or below that time.
- **SLO** - an internal target (e.g. 99.9% success over 30 days).
- **SLA** - the contractual promise to customers - usually a *weaker* target than
  the SLO, so internal alerts fire before the contract is breached.
- **Error budget** = `1 − SLO`. At 99.9%, the system may spend about 43 minutes
  per month on errors. **Burn rate** = how fast that budget is consumed; alert
  when burn is too high, meaning the service is on track to exhaust the monthly
  budget early.

## How it works

The app already exposes `http_requests_total` (observability), so the SLO is computed
directly in Prometheus. The provisioned dashboard's **"SLO & error budget"** row
renders three panels from these queries. (`rate(...[30m])` = the per-second rate
averaged over the last 30 minutes; `status=~"5.."` = a regex matching HTTP 5xx
error codes - server failures; `status!~"5.."` = everything that is *not* a 5xx,
i.e. the successes):

```text
# success ratio (SLI) over 30m
sum(rate(http_requests_total{status!~"5.."}[30m]))
  / sum(rate(http_requests_total[30m]))

# fast-burn alert: error rate vs a 99.9% objective over 1h
( sum(rate(http_requests_total{status=~"5.."}[1h]))
  / sum(rate(http_requests_total[1h])) ) / 0.001
```

## Run

```bash
make availability    # Grafana: http://localhost:3001
./modules/availability/demo.sh
make load               # generate traffic; observe RED + SLO/error-budget panels
```


## How to read the commands

Read `make availability` as starting the measurement system, not changing
the application contract. Read `./modules/availability/demo.sh` as the guided
math-and-observation walkthrough. Read `make load` as creating enough traffic
for SLI, SLO, and burn-rate panels to have useful data. **RED** means Rate,
Errors, and Duration; it is a common dashboard pattern for service health.

## How to read the output

In Grafana, read the success ratio as the measured SLI. Read the error budget as
remaining tolerance for bad requests before the SLO is missed. Read burn rate as
the speed at which that budget is being consumed.

Do not read a single red point as the whole story. Ask three questions in order:
what user-visible behavior is being measured, over what time window, and how fast
is the budget being spent? A short spike may be acceptable if the monthly budget
barely moves; a smaller sustained error rate may be dangerous if it burns the
budget for hours.

## What to observe

1. The **success-ratio** SLI sits near 100% under normal load (green).
2. Inject errors (kill a replica, or `SLOW=1` to breach the latency SLO) and the
   ratio dips - the **error budget** gauge starts draining.
3. A **fast-burn** condition (burn rate ≫ 1) is exactly what a good alert fires
   on - not every single error.

For each panel, write one sentence in this form:

```text
This panel proves _____ because the measured _____ changed from _____ to _____.
```

## What you learned

- Availability is measured over time, not by whether a system seems healthy once.
- Serial dependencies multiply failure risk along the request path.
- Redundancy can improve availability, but only when failures are independent enough.
- Reliability targets should shape design choices before implementation details.

## Practice experiments

1. Compute monthly downtime for 99%, 99.9%, and 99.99% availability.
2. Generate load, then explain which panel answers "are users affected?".
3. Design one alert based on burn rate instead of raw error count.

## Trade-offs

- More nines cost exponentially more (redundancy, testing, on-call); pick the
  lowest-cost target the business needs.
- Alerting on raw errors causes fatigue; alerting on **burn rate** ties pages to
  budget impact.
- An SLO that is always met is too loose; one that is always missed is unrealistic.

## Next steps

- [Replication and failover](../replication-failover/README.md) for a concrete availability mechanism.
- [Multi-region, DR and backups](../multi-region-dr/README.md) for recovery planning.
- [Observability](../observability/README.md) for measuring reliability signals.

## Further reading

- Google SRE Book - "Service Level Objectives": https://sre.google/sre-book/service-level-objectives/
- Google SRE Workbook - "Alerting on SLOs" (multi-window burn rate):
  https://sre.google/workbook/alerting-on-slos/
- Brendan Gregg, "The USE Method" (resource-side reliability):
  https://www.brendangregg.com/usemethod.html

## Cleanup

```bash
make reset
```
