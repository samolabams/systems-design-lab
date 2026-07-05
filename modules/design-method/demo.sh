#!/usr/bin/env bash
# The design method: build a justified first-pass design artifact.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

echo "${BOLD}The design method${RESET}"
note "No containers are required. This is a guided design exercise using the same predict/checkpoint loop as runnable labs."
note "Use a notebook or scratch file; the output is a design artifact, not terminal output."

step "Clarify requirements before tools" \
     "functional requirements and constraints decide the design shape"
predict "For a short-link service, what are the two core user-visible operations?" \
        "Create a short code for a long URL, and resolve a short code into a redirect."
note "Write two lists: functional requirements and non-functional requirements."
note "Functional: create link, redirect by code. Non-functional: low redirect latency, durable mappings, high read availability."
checkpoint "Which requirement would justify analytics infrastructure?" \
           "A requirement to count clicks or report usage; without it, analytics is optional complexity."
pause

step "Estimate scale" \
     "numbers turn guesses into component pressure"
predict "If reads are 100x writes, which path should receive the most design attention?" \
        "The redirect/read path, because it dominates traffic and user-visible latency."
note "Example assumption: 100 writes/sec, 10,000 reads/sec, 5 years of links, redirect p95 under 100 ms."
note "Back-of-envelope: writes are modest, reads are hot, storage is durable but not enormous for a first pass."
checkpoint "What component becomes easier to justify after a 10,000 reads/sec estimate?" \
           "A cache on the redirect path, because repeated hot-code reads can avoid database work."
pause

step "Draw the high-level design" \
     "start simple, then add only the components demanded by requirements"
note "First pass: client -> gateway -> link service -> database."
note "Read-heavy pass: client -> gateway -> link service -> cache -> database on miss."
note "Analytics pass: redirect event -> queue/log -> worker -> analytics store."
checkpoint "Why is the database still in the design after adding a cache?" \
           "The cache is an acceleration layer; the database remains the durable source of truth."
pause

step "Choose components by pressure" \
     "each component needs a reason tied to a requirement or estimate"
predict "Which is justified first for this workload: cache, shard, or queue?" \
        "Cache first for read latency/offload; queue only if analytics is required; shard only after a write/storage ceiling is measured."
note "Relational database: durable code -> URL mapping and uniqueness."
note "Cache: hot redirect reads."
note "Queue/log: analytics side effects that should not slow redirects."
note "Partitioning: later, if one database cannot hold or write the mapping set."
checkpoint "What indicates that a component was added too early?" \
           "No requirement, estimate, bottleneck, or failure mode explains why it exists."
pause

step "Analyze bottlenecks and trade-offs" \
     "state what the design improves and what it gives up"
try_it "Write one bottleneck statement and one trade-off statement for the short-link service." \
       "Example: reads dominate, so cache hot redirects; this risks brief staleness after deletes or updates."
checkpoint "What should a complete first-pass answer contain?" \
           "Requirements, estimates, API/data model, high-level design, component justifications, bottlenecks, and trade-offs."
note "Grade the artifact with modules/design-method/method.md, then repeat with a capstone."

echo
note "${BOLD}Done.${RESET} Cleanup: nothing to tear down."