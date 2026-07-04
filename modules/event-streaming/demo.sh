#!/usr/bin/env bash
# €” Kafka: partitions, consumer groups, and replay from offset 0.
# Contrast with async queues's queue-and-delete model. Pausable.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile event-streaming"
# The official apache/kafka image keeps the CLI tools in /opt/kafka/bin but does
# not put them on PATH, so we add it for the exec'd shell.
K="$COMPOSE exec -T -e PATH=/opt/kafka/bin:/usr/bin:/bin kafka"
BS="--bootstrap-server localhost:9092"
TOPIC="events"

echo "${BOLD}€” Event log & streaming (Kafka)${RESET}"
note "Assumes 'make event-streaming' is running. Kafka UI: http://localhost:8081"

step "Create a topic with 3 partitions" "ordering is per-partition; partitions give parallelism"
run "$K kafka-topics.sh $BS --create --if-not-exists --topic $TOPIC --partitions 3 --replication-factor 1"
run "$K kafka-topics.sh $BS --describe --topic $TOPIC"
pause

step "Produce keyed events" "same key -> same partition (kept in order)"
run "printf 'user1:login\\nuser1:click\\nuser2:login\\nuser3:login\\nuser2:logout\\nuser1:logout\\n' | $K kafka-console-producer.sh $BS --topic $TOPIC --property parse.key=true --property key.separator=:"
note "6 events written across 3 partitions, keyed by user."
pause

step "Consume with a consumer group" "reads each event once across the group"
run "$K kafka-console-consumer.sh $BS --topic $TOPIC --group analytics --from-beginning --timeout-ms 6000 --property print.key=true 2>/dev/null || true"
pause

step "Show the group's committed offsets" "where 'analytics' has read up to, per partition"
run "$K kafka-consumer-groups.sh $BS --describe --group analytics || true"
pause

step "Replay from the beginning with a NEW group" "the log was NOT deleted â€” every event returns"
run "$K kafka-console-consumer.sh $BS --topic $TOPIC --group audit --from-beginning --timeout-ms 6000 --property print.key=true 2>/dev/null || true"
note "RabbitMQ (async queues) would have deleted these on ack. Kafka keeps the log for replay."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
