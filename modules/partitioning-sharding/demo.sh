#!/usr/bin/env bash
# Partitioning & sharding. Compare naive modulo sharding with
# a consistent-hash ring by measuring how many keys MOVE when a node is added.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile partitioning-sharding"
DEMO_DIR="$REPO_ROOT/modules/partitioning-sharding"

echo "${BOLD}Partitioning & sharding${RESET}"
note "Assumes 'make partitioning-sharding' is running (base stack)."
note "Learning loop: predict key movement, run the comparison, then connect movement to operational cost."

step "The problem" "one node can't hold everything - split keys across N nodes"
note "The hard part isn't splitting; it's what happens when N changes (a node is"
note "added for growth, or removed on failure). How many keys have to move?"
predict "If hash(key) % N uses N=4 and then N=5, what happens to most key assignments?" \
     "Most assignments change because the divisor changed for every key."
checkpoint "Why is moving keys expensive in a real database?" \
	"It means copying data, rebuilding cache locality, updating routing, and absorbing migration load."
pause

step "Measure key movement: modulo vs consistent ring" "modulo reshuffles ~everything; the ring moves ~1/N"
note "10,000 keys across 4 nodes, then we add a 5th and recount."
predict "Which strategy should move fewer keys when adding one node?" \
     "Consistent hashing, because the new node takes only part of the ring instead of changing every modulo result."
run "docker run --rm -v \"$DEMO_DIR\":/demo:ro cgr.dev/chainguard/node:latest@sha256:5280e63c3d2c81366056926b79f27f70e4adbd3a03a5b45c53503eac2b722b3f /demo/shard.js"
checkpoint "Why is lower movement more important than a perfectly even split during growth?" \
	"Less movement reduces migration risk and keeps more cached or colocated data useful while the cluster changes."
pause

step "Why it matters" "moved keys = cache misses, data copies, rebalancing load"
note "With hash(key) % N, changing N changes the divisor, so almost every key maps"
note "somewhere new - a near-total reshuffle. For a cache that's a mass miss storm;"
note "for a database it's copying most of your data."
note "A consistent-hash RING places nodes and keys on the same circle; a key is"
note "owned by the next node clockwise. Adding a node only steals the slice between"
note "it and its predecessor - so only ~K/N keys move. Virtual nodes keep the"
note "slices even. This is how Dynamo, Cassandra, and memcached clients shard."

step "Mini challenge" "decide when sharding is actually justified"
try_it "Name the metric that would force this module into a real design." \
       "Examples: one database node cannot hold the data set, sustain write QPS, or rebalance within the maintenance window."
checkpoint "Why is sharding a late move instead of an early default?" \
	"It adds routing, rebalancing, hot-key handling, cross-shard query limits, and operational migration work."

echo
note "${BOLD}Done.${RESET} Cleanup: make reset"
