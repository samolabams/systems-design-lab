#!/usr/bin/env bash
# Partitioning & sharding. Compare naive modulo sharding with
# a consistent-hash ring by measuring how many keys MOVE when a node is added.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile partitioning-sharding"
DEMO_DIR="$REPO_ROOT/modules/partitioning-sharding"

echo "${BOLD}Partitioning & sharding${RESET}"
note "Assumes 'make partitioning-sharding' is running (base stack)."

step "The problem" "one node can't hold everything — split keys across N nodes"
note "The hard part isn't splitting; it's what happens when N changes (a node is"
note "added for growth, or removed on failure). How many keys have to move?"
pause

step "Measure key movement: modulo vs consistent ring" "modulo reshuffles ~everything; the ring moves ~1/N"
note "10,000 keys across 4 nodes, then we add a 5th and recount."
run "docker run --rm -v \"$DEMO_DIR\":/demo:ro node:22-alpine node /demo/shard.js"
pause

step "Why it matters" "moved keys = cache misses, data copies, rebalancing load"
note "With hash(key) % N, changing N changes the divisor, so almost every key maps"
note "somewhere new — a near-total reshuffle. For a cache that's a mass miss storm;"
note "for a database it's copying most of your data."
note "A consistent-hash RING places nodes and keys on the same circle; a key is"
note "owned by the next node clockwise. Adding a node only steals the slice between"
note "it and its predecessor — so only ~K/N keys move. Virtual nodes keep the"
note "slices even. This is how Dynamo, Cassandra, and memcached clients shard."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
