//  A hand-rolled circuit breaker wrapping a flaky dependency.
//
// Run with Node (no dependencies):  node breaker.js
//
// The breaker has three states:
//   CLOSED     — calls pass through. Consecutive failures are counted; when they
//                reach the threshold the breaker trips to OPEN.
//   OPEN       — calls fail FAST (no call to the dependency) for a cool-down
//                window, giving the struggling dependency room to recover.
//   HALF_OPEN  — after the cool-down, ONE probe call is allowed through. If it
//                succeeds the breaker closes; if it fails it re-opens.
//
// This is the pattern that stops a slow/failing dependency from exhausting your
// threads, connections, and latency budget and cascading into a full outage.

'use strict';

// --- A flaky downstream dependency -----------------------------------------
// Healthy for the first second, then "goes down" (always fails) for 3s, then
// recovers. Each call also has a timeout, modelling a slow dependency.
const START = Date.now();
function flakyDependency() {
  return new Promise((resolve, reject) => {
    const elapsed = Date.now() - START;
    const down = elapsed > 1000 && elapsed < 4000; // outage window
    const latency = down ? 400 : 30;
    setTimeout(() => {
      if (down) reject(new Error('dependency 500'));
      else resolve('ok');
    }, latency);
  });
}

// --- The circuit breaker ----------------------------------------------------
class CircuitBreaker {
  constructor(fn, { failureThreshold = 3, cooldownMs = 1500, callTimeoutMs = 200 } = {}) {
    this.fn = fn;
    this.failureThreshold = failureThreshold;
    this.cooldownMs = cooldownMs;
    this.callTimeoutMs = callTimeoutMs;
    this.state = 'CLOSED';
    this.failures = 0;
    this.openedAt = 0;
  }

  async call() {
    // OPEN: fail fast until the cool-down elapses, then allow one probe.
    if (this.state === 'OPEN') {
      if (Date.now() - this.openedAt < this.cooldownMs) {
        throw new Error('circuit OPEN — failing fast');
      }
      this._to('HALF_OPEN');
    }

    try {
      const result = await this._withTimeout(this.fn());
      this._onSuccess();
      return result;
    } catch (err) {
      this._onFailure();
      throw err;
    }
  }

  _withTimeout(promise) {
    return Promise.race([
      promise,
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('timeout')), this.callTimeoutMs)
      ),
    ]);
  }

  _onSuccess() {
    if (this.state === 'HALF_OPEN') this._to('CLOSED');
    this.failures = 0;
  }

  _onFailure() {
    // A failed probe in HALF_OPEN immediately re-opens the breaker.
    if (this.state === 'HALF_OPEN') {
      this._open();
      return;
    }
    this.failures += 1;
    if (this.failures >= this.failureThreshold) this._open();
  }

  _open() {
    this._to('OPEN');
    this.openedAt = Date.now();
    this.failures = 0;
  }

  _to(next) {
    if (this.state !== next) {
      console.log(`    breaker: ${this.state} -> ${next}`);
    }
    this.state = next;
  }
}

// --- Driver: hit the dependency 20 times, 250ms apart -----------------------
async function main() {
  const breaker = new CircuitBreaker(flakyDependency, {
    failureThreshold: 3,
    cooldownMs: 1500,
    callTimeoutMs: 200,
  });

  let fastFails = 0;
  for (let i = 1; i <= 20; i++) {
    const t = ((Date.now() - START) / 1000).toFixed(1);
    try {
      const r = await breaker.call();
      console.log(`t=${t}s  req ${String(i).padStart(2)}  OK    (${breaker.state}) -> ${r}`);
    } catch (err) {
      const fast = err.message.includes('OPEN');
      if (fast) fastFails++;
      console.log(
        `t=${t}s  req ${String(i).padStart(2)}  FAIL  (${breaker.state}) -> ${err.message}`
      );
    }
    await new Promise((r) => setTimeout(r, 250));
  }

  console.log(
    `\nSummary: ${fastFails} requests failed FAST while the circuit was OPEN — ` +
      `those never touched the struggling dependency.`
  );
}

main();
