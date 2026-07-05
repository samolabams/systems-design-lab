#!/usr/bin/env bash
# Circuit breakers. Run a hand-rolled breaker against a dependency
# that fails for a few seconds and watch it trip OPEN (fail fast), then probe in
# HALF_OPEN, then close again once the dependency recovers.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile circuit-breakers"
DEMO_DIR="$REPO_ROOT/modules/circuit-breakers"

echo "${BOLD}Circuit breakers${RESET}"
note "Assumes 'make circuit-breakers' is running (base stack)."
note "Learning loop: predict state transitions, run the dependency outage, then explain which calls were protected."

step "Inspect the breaker" "three states: CLOSED -> OPEN -> HALF_OPEN -> CLOSED"
note "breaker.js wraps a flaky dependency (healthy, then a 3s outage, then heals)"
note "with a hand-rolled breaker: 3 consecutive failures trip it OPEN; after a"
note "1.5s cooldown it allows ONE probe (HALF_OPEN); a good probe closes it."
predict "What should happen after three consecutive dependency failures?" \
     "The breaker should move from CLOSED to OPEN and fail new calls immediately."
checkpoint "What problem does OPEN state avoid?" \
	"It avoids spending every caller's time and resources waiting on a dependency that is already failing."
pause

step "Run the breaker against the failing dependency" "watch the state transitions and the FAIL FAST window"
note "Each call has a 200ms timeout; 20 requests, 250ms apart."
predict "During the outage, which calls should be fastest: timed-out calls or fail-fast calls?" \
     "Fail-fast calls should be much faster because they do not wait for the 200ms dependency timeout."
run "docker run --rm -v \"$DEMO_DIR\":/demo:ro cgr.dev/chainguard/node:latest@sha256:5280e63c3d2c81366056926b79f27f70e4adbd3a03a5b45c53503eac2b722b3f /demo/breaker.js"
checkpoint "Which output lines prove the breaker recovered instead of staying open forever?" \
	"Look for HALF_OPEN/probe behavior followed by CLOSED or successful calls after the dependency heals."
pause

step "What just happened" "the breaker shielded the caller from the outage"
note "1. CLOSED while healthy - calls pass."
note "2. The dependency starts failing; after 3 failures the breaker trips OPEN."
note "3. While OPEN, calls fail in microseconds (FAIL FAST) instead of waiting on"
note "   a 200ms timeout each - that is what stops thread/connection exhaustion."
note "4. After the cooldown a HALF_OPEN probe tests the dependency; once it succeeds"
note "   the breaker returns to CLOSED and normal traffic resumes."
note "In a real service you wrap each downstream dependency in its own breaker and"
note "export the state as a metric so dashboards/alerts can see it trip."

step "Mini challenge" "tune the thresholds and predict the blast radius"
try_it "Open modules/circuit-breakers/breaker.js and inspect the failure threshold, timeout, and reset timeout." \
       "Lower thresholds trip faster but may reject healthy traffic during brief blips; higher thresholds tolerate noise but expose callers longer."
checkpoint "What is the trade-off in every breaker configuration?" \
	"Sensitivity versus false positives: trip too early and shed useful calls; trip too late and callers pile up behind a bad dependency."

echo
note "${BOLD}Done.${RESET} Cleanup: make reset"
