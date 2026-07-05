#!/usr/bin/env bash
# Availability and reliability math: compute nines and connect them to observable SLO signals.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

echo "${BOLD}Availability & reliability math${RESET}"
note "Assumes 'make availability' is running if you want to inspect Grafana after the calculations."
note "This demo starts with arithmetic, then connects the numbers to the lab's Prometheus/Grafana signals."

calc_downtime() {
  awk -v availability="$1" 'BEGIN {
    unavailable = 1 - availability;
    minutes_year = unavailable * 365 * 24 * 60;
    minutes_month = unavailable * 30 * 24 * 60;
    printf "availability=%.3f%% downtime/year=%.2f minutes downtime/month=%.2f minutes\n", availability * 100, minutes_year, minutes_month;
  }'
}

step "Turn nines into time" \
     "availability targets become downtime budgets"
predict "Which target allows more monthly downtime: 99.9% or 99.99%?" \
        "99.9% allows about ten times more downtime than 99.99%."
run "calc_downtime 0.99"
run "calc_downtime 0.999"
run "calc_downtime 0.9999"
checkpoint "Why is 'highly available' incomplete without a number?" \
           "The cost and design differ drastically between one hour and a few minutes of yearly downtime."
pause

step "Series dependencies multiply risk" \
     "a request path is only as available as the components it requires"
predict "If gateway, app, and database are each 99.9% available in series, is the path still 99.9%?" \
        "No. Series availability multiplies, so the full path is lower."
run "awk 'BEGIN { path=0.999*0.999*0.999; printf \"gateway*app*db = %.5f%% available\\n\", path*100 }'"
checkpoint "What design pressure does this create?" \
           "Every required dependency spends reliability budget, so avoid unnecessary critical-path dependencies."
pause

step "Parallel redundancy cuts failure probability" \
     "replicas help when one healthy copy can serve the request"
predict "Two independent 99% replicas behind a balancer should be closer to which target: 99%, 99.9%, or 99.99%?" \
        "99.99%, because both must fail at the same time for the redundant tier to be down."
run "awk 'BEGIN { a=0.99; redundant=1-((1-a)*(1-a)); printf \"two 99%% replicas = %.4f%% available\\n\", redundant*100 }'"
checkpoint "What assumption makes that math optimistic?" \
           "Failures must be mostly independent; shared bugs, shared deploys, and shared dependencies reduce the benefit."
pause

step "Connect math to SLO signals" \
     "Prometheus turns request outcomes into an SLI"
note "In Grafana, open http://localhost:3001 and inspect the SLO & error-budget row."
note "Success ratio is the SLI; error budget is the allowed bad-request fraction; burn rate is how fast it is being consumed."
try_it "Run make load, then explain which panel answers 'are users currently affected?'" \
       "Use success ratio and latency/error panels together; raw error count alone is not enough."
checkpoint "Why alert on burn rate instead of every error?" \
           "Burn rate pages when the SLO is being consumed too quickly, reducing noise from harmless isolated failures."

echo
note "${BOLD}Done.${RESET} Cleanup: make reset"