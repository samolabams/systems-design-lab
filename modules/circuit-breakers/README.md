# Circuit breakers

**Track:** Components
**Prerequisites:** none

## Outcome

After this module, you should understand a circuit breaker as a
state machine for preventing cascading failure. You should be able to
explain:

1. Why slow downstream dependencies can exhaust callers.
2. What CLOSED, OPEN, and HALF_OPEN states mean.
3. Why failing fast protects latency budgets and connection pools.
4. How timeouts, retries, backoff, jitter, and fallbacks interact with breakers.
5. Why breakers should be scoped per downstream dependency.
6. Which breaker state transitions should be monitored.

## What you will build or run

1. A failing downstream dependency scenario that makes timeouts and retries visible.
2. A circuit breaker state transition from closed to open and back toward recovery.
3. Requests that show the difference between slow failure and fast failure.
4. A set of tuning questions for thresholds, cooldowns, and fallback behavior.

## Why this matters

When a downstream dependency becomes slow or starts failing, repeatedly calling
it can make the failure worse. Every in-flight call holds a thread and a
connection while waiting for a timeout, so one unhealthy dependency can drain the
caller pool and latency budget until the caller fails as well. That is a
**cascading failure**. A circuit breaker detects the problem and **fails fast**,
shielding the caller and giving the dependency room to recover.

## Concept

A breaker is a small state machine wrapped around a remote call:

- **CLOSED** - calls pass through. Count consecutive failures; when they reach a
  threshold, **trip** to OPEN.
- **OPEN** - short-circuit: return an error (or fallback) **immediately** without
  calling the dependency, for a cooldown period. This is the key move - failing
  in microseconds instead of waiting on a timeout per call.
- **HALF_OPEN** - after the cooldown, let **one** probe through. Success moves to
  CLOSED (recovered). Failure moves back to OPEN (still sick).

Companions to a breaker:
- **Timeout** - never wait forever; bound every remote call.
- **Retry with backoff + jitter** - retry *transient* errors, but spread retries
  out so clients do not synchronize a thundering herd.
- **Fallback** - serve cached/default data when the breaker is open, where a safe fallback exists.

The whole pattern in language-neutral pseudocode - no JavaScript required:

```text
on call(request):
    if state == OPEN:
        if now - opened_at >= cooldown:   # cooldown elapsed; try one probe
            state = HALF_OPEN
        else:
            return error "circuit OPEN - failing fast"   # shed instantly

    try:
        result = dependency(request) with timeout(call_timeout)
        on success:
            failures = 0
            if state == HALF_OPEN: state = CLOSED   # probe healed; recover
            return result
    on failure or timeout:
        failures += 1
        if state == HALF_OPEN or failures >= threshold:
            state = OPEN; opened_at = now           # trip / re-trip
        return error
```

## How it works

The demo's engine is a small script (`breaker.js`) that implements exactly the
pseudocode above, with `threshold=3`, `cooldown=1.5s`, `call_timeout=200ms`. It
simulates a dependency that is healthy, fails for a roughly 3-second window, then
recovers, and pushes 20 calls through the breaker. Read the output first, then
inspect `breaker.js` if you want to see how the pseudocode becomes executable
code. `demo.sh` runs it in a temporary hardened Node container and prints
every state transition and each call's outcome.

> The **pseudocode above is the reference algorithm**. `breaker.js` is one
> illustrative implementation used to execute it.

## Run

```bash
pwd
make circuit-breakers
./modules/circuit-breakers/demo.sh
```

The output of `pwd` should end with `systems-design`.

## How to read the commands

The demo runs a small breaker simulation in a temporary Node container. The
important parameters are:

| Parameter | Meaning |
|---|---|
| `threshold=3` | trip after three consecutive failures |
| `cooldown=1.5s` | wait before allowing a probe |
| `call_timeout=200ms` | bound each dependency call |

Read the command as: send repeated calls through the breaker while the simulated
dependency becomes unhealthy and then recovers.

## How to read the output

Look for state transitions rather than individual implementation details:

```text
CLOSED (passing calls through)
  -> OPEN (failing fast)
  -> HALF_OPEN (testing one probe)
  -> CLOSED (recovered)
```

Failures before OPEN prove the breaker is measuring dependency health. Immediate
failures while OPEN prove the caller is no longer waiting on the dependency.
The HALF_OPEN probe proves recovery is tested cautiously before normal traffic
resumes.

## What to observe

1. **CLOSED / healthy** - the first calls return `OK`.
2. **Tripping** - once the dependency starts failing, three failures flip the
   breaker `CLOSED -> OPEN`.
3. **Fail fast** - while `OPEN`, calls return `circuit OPEN - failing fast`
   instantly; they never touch the dependency or pay the 200ms timeout. The
   summary line counts how many were shed this way.
4. **Probe & recover** - after the cooldown the breaker goes `OPEN -> HALF_OPEN`,
   a probe succeeds once the dependency heals, and it returns `HALF_OPEN ->
   CLOSED`.

## What you learned

- Timeouts bound how long callers wait for a dependency.
- Retries can help transient failures but can also amplify overload.
- Circuit breakers protect callers and dependencies by failing fast during unhealthy periods.
- Fallbacks must be chosen deliberately because they affect user-visible correctness.

## Practice experiments

1. Change the failure threshold in `breaker.js` and predict when OPEN appears.
2. Change the cooldown and observe how often probes are allowed.
3. Decide what safe fallback could exist for a read endpoint.
4. Explain why retries without jitter can make an outage worse.

## Trade-offs

- **Threshold & cooldown tuning** - trip too eagerly and you reject during blips;
  trip too late and the breaker does not protect anything. Tune to the dependency's real
  failure profile.
- **Fail fast vs availability** - an open breaker trades a *correct* slow answer
  for a *fast* error (or fallback). That is usually right, but a fallback that
  serves stale data has its own correctness cost.
- **Per-dependency, not global** - one breaker per downstream. A shared breaker
  would let one sick dependency cut off healthy ones.
- **Retry storms** - breakers and retries interact: always add jitter, and do not
  retry through an open breaker.

## Next steps

- [Availability](../availability/README.md) for reliability math.
- [Observability](../observability/README.md) for detecting failure patterns.
- [Rate limiting](../rate-limiting/README.md) for controlling incoming pressure.

## Further reading

- Martin Fowler, "CircuitBreaker":
  https://martinfowler.com/bliki/CircuitBreaker.html
- Michael Nygard, *Release It!* - Circuit Breaker & Bulkhead stability patterns.
- AWS Builders' Library, "Timeouts, retries and backoff with jitter":
  https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/
- Netflix Hystrix wiki (the canonical implementation):
  https://github.com/Netflix/Hystrix/wiki

## Cleanup

```bash
make reset
```
