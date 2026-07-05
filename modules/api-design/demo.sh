#!/usr/bin/env bash
# API design: REST vs gRPC vs GraphQL. Standing up real gRPC and
# GraphQL servers would drag in heavy toolchains; instead we demonstrate the
# parts that are *measurable* with a dependency-free Node script run inside the
# existing `app` container (node-alpine): the real Protobuf wire size vs JSON,
# and how GraphQL field-selection removes REST's over-fetch and round trips.
# The qualitative trade-offs (streaming, caching, coupling) are called out as we
# go. No new service or compose change.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose"
SCRIPT="$(dirname "$0")/compare.js"

# Run the comparison script inside the app container; `node` with no args reads
# the program from stdin, so we pipe the file in and pick a section via SECTION.
runjs() { $COMPOSE exec -T -e "SECTION=$1" app node < "$SCRIPT"; }

echo "${BOLD}API design: REST vs gRPC vs GraphQL${RESET}"
note "Demonstration runs inside the base 'app' container (Node) — no extra services."

step "Wire size: JSON vs Protobuf" "the same record, binary vs text on the wire"
runjs wire
pause

step "GraphQL vs REST: over-fetch and round trips" "ask for exactly the fields you need, in one request"
runjs graphql
pause

step "Schema evolution & streaming" "how each contract adds a field without breaking clients"
runjs evolve
pause

step "Choosing the contract" "match API style to access pattern and clients"
runjs choose
pause

step "Operational checklist" "the guardrails each API style needs in production"
runjs operate
note "Pick by problem shape: REST for ubiquity/caching, gRPC for fast service-to-service + streaming, GraphQL for client-tailored reads over many resources."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
