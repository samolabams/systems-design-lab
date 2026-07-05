#!/usr/bin/env bash
# Component selection: turn requirements into justified building blocks.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

echo "${BOLD}Component selection${RESET}"
note "No containers are required. This is a decision workshop for design documents and capstones."
note "The goal is to choose categories first, then products, with an explicit trade-off for each."

step "Extract the pressure" \
     "requirements point at component categories"
predict "Problem: users upload profile photos and others view them often. Which data is blob-like, and which is relational metadata?" \
        "Image bytes are blobs; owner ID, moderation status, object key, and timestamps are relational metadata."
checkpoint "Why should the category be named before the product?" \
           "It prevents choosing familiar technology before the requirement is understood."
pause

step "Choose storage" \
     "different data shapes deserve different stores"
note "Large immutable bytes -> object store."
note "Small constrained metadata -> relational database."
note "Repeated public reads -> edge cache/CDN if the content is cacheable."
checkpoint "Why not store images directly in the relational table by default?" \
           "Large blobs inflate backups, scans, and row IO; object stores are built for durable blob serving."
pause

step "Choose messaging" \
     "queues and logs solve different temporal problems"
predict "If consumers need to replay all historical events, should the design use a queue or a log?" \
        "A log, because it retains events and lets each consumer track its own offset."
note "Queue: competing consumers, work disappears after ack."
note "Log: replayable history, multiple independent consumers, retention/offset operations."
checkpoint "What question decides RabbitMQ/SQS versus Kafka-style logs?" \
           "Does the system need replayable event history for multiple consumers?"
pause

step "Reject unjustified machinery" \
     "every component should remove a named bottleneck or satisfy a named constraint"
try_it "For a small CRUD admin app, decide whether Kafka, Redis, and sharding are justified." \
     "Usually not, unless requirements name replay, hot repeated reads, or a measured write/storage ceiling."
checkpoint "What should appear beside every component in a design review?" \
           "The requirement or estimate that needs it, plus the cost it introduces."
pause

step "Write the component table" \
     "the artifact is a rationale, not a shopping list"
try_it "Create columns: Requirement, category, product, why, trade-off." \
       "Example: fast repeated image reads -> CDN/edge cache -> Nginx edge lab -> origin offload -> possible stale content until TTL expires."
checkpoint "How do you know the selection is complete enough for a first pass?" \
           "Core data, request entry point, async work, cache strategy, and failure trade-offs are covered without unsupported extras."

echo
note "${BOLD}Done.${RESET} Cleanup: nothing to tear down."