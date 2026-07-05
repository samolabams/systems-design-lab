#!/usr/bin/env bash
# Consistency models: map abstract guarantees to the runnable replication and election labs.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

echo "${BOLD}CAP / PACELC & consistency models${RESET}"
note "This module is a guided map across existing labs. Start the named profile before running each linked demo."
note "Use AUTO=1 with the underlying demos if you want to skip pauses."

step "Strong reads" \
     "reading from the primary sees committed writes on that path"
predict "After writing a link on the primary, which read path should see it immediately?" \
        "A read from the primary, because it is the source that accepted the committed write."
note "Run: make replication-failover"
note "Then run: ./modules/replication-failover/demo.sh"
checkpoint "What is the cost of routing all reads to the primary?" \
           "Simple freshness, but limited read scale and more pressure on the leader."
pause

step "Eventual consistency" \
     "an async replica can lag but should converge"
predict "What can happen if a client writes to the primary and immediately reads from an async replica?" \
        "The read may miss the new value until replication catches up."
note "In the replication-failover demo, inspect the read-after-write hazard and lag output."
checkpoint "Is a temporary miss necessarily a bug?" \
           "No. It may be exactly the eventual-consistency contract; the application must decide whether that is acceptable."
pause

step "Monotonic reads and read-your-writes" \
     "client routing can provide stronger behavior for one user"
predict "What user-visible problem appears when two reads hit replicas at different lag positions?" \
        "The user can see time go backward: data appears, disappears, then reappears."
note "A common mitigation is to pin a client to one replica or route recent writer reads to the primary for a short window."
checkpoint "Which guarantee does primary-after-write routing protect?" \
           "Read-your-writes for that client."
pause

step "CAP during a partition" \
     "leader election chooses one history over always accepting writes"
predict "During a partition, what should a CP replica set prefer: reject some writes or risk divergent histories?" \
        "Reject some writes, preserving one consistent history."
note "Run: make leader-election-replica-sets"
note "Then run: ./modules/leader-election-replica-sets/demo.sh"
checkpoint "What does CP give up during the partition?" \
           "Availability for clients that cannot reach the majority/leader."
pause

step "PACELC in the normal case" \
     "even without partitions, systems trade latency against consistency"
try_it "Classify the async read replica: Else-Latency or Else-Consistency?" \
       "EL: when there is no partition, it favors low-latency/read-scale over freshest possible reads."
checkpoint "Why is PACELC often more useful than CAP in day-to-day design?" \
           "Most design choices happen when the network is healthy, where the trade is often latency versus freshness."

echo
note "${BOLD}Done.${RESET} Cleanup after linked labs: make reset"