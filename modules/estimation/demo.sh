#!/usr/bin/env bash
# Back-of-the-envelope estimation: guided measurement wrapper.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

echo "${BOLD}Back-of-the-envelope estimation${RESET}"
note "Assumes 'make estimation' or 'make base' is running."
note "This script runs the measurement pass, then points back to estimate.md for the worksheet."

step "Calibrate estimates against this lab" \
     "real latency measurements keep design math grounded"
predict "Before measuring, which path should be slower: a full HTTP shorten request or a database-only point read?" \
        "The full HTTP request should be slower because it includes more components and network hops."
AUTO="${AUTO:-0}" "$(dirname "$0")/measure.sh"
note "Use these measurements as order-of-magnitude evidence before adding cache, queue, replica, or shard complexity."
note "Next: fill out modules/estimation/estimate.md. Cleanup: make reset"