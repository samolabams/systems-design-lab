#!/usr/bin/env bash
# Message delivery semantics, outbox & idempotency. Kafka (event streaming)
# gives at-least-once delivery, so a retry double-acts unless the consumer is
# idempotent. This demo proves effectively-once processing with the OUTBOX
# pattern (Postgres) + consumer-side dedup, then REPLAYs the log to show
# duplicates are absorbed.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile message-delivery-semantics"
PSQL="$COMPOSE exec -T -e PGPASSWORD=app postgres-primary psql -U app -d app"
K="$COMPOSE exec -T -e PATH=/opt/kafka/bin:/usr/bin:/bin kafka"
BS="--bootstrap-server localhost:9092"
TOPIC="outbox.orders"

# Process one event id: dedup on processed_events; only NEW events fire the side
# effect (a confirmation notification). A duplicate is a no-op. We wrap the
# idempotent INSERT in a CTE and SELECT count(*) so the result is a clean 0/1 —
# a bare "INSERT ... RETURNING" prints the "INSERT 0 0" command tag even on a
# conflict, which would read as non-empty and defeat the dedup.
process_event() {
  local eid="$1" inserted
  inserted=$($PSQL -tA -c "WITH ins AS (INSERT INTO processed_events(event_id) VALUES ('$eid') ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*) FROM ins" </dev/null | tr -d '[:space:]')
  if [ "$inserted" = "1" ]; then
    $PSQL -q -c "INSERT INTO notifications(order_id, note) SELECT order_id, 'confirmation sent' FROM outbox_messages WHERE event_id='$eid'" </dev/null
    echo "    $eid -> NEW: notification sent"
  else
    echo "    $eid -> duplicate: skipped (effectively-once)"
  fi
}

# Consume the whole topic from the start under a fresh group, dedup each event.
consume_with_dedup() {
  local group="$1" events
  events=$($K kafka-console-consumer.sh $BS --topic "$TOPIC" --group "$group" --from-beginning --timeout-ms 7000 2>/dev/null || true)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    process_event "${line%%|*}"
  done <<< "$events"
}

count() { $PSQL -tA -c "$1" </dev/null | tr -d '[:space:]'; }

echo "${BOLD}Message delivery semantics, outbox & idempotency${RESET}"
note "Assumes 'make message-delivery-semantics' is running (base Postgres + Kafka)."

step "Set up the outbox tables and topic" "orders, outbox, processed (dedup), notifications (side effect)"
$PSQL -q <<'SQL'
DROP TABLE IF EXISTS orders, outbox_messages, processed_events, notifications;
CREATE TABLE orders        (id text PRIMARY KEY, item text, amount int);
CREATE TABLE outbox_messages        (event_id text PRIMARY KEY, order_id text, payload text, published boolean DEFAULT false);
CREATE TABLE processed_events     (event_id text PRIMARY KEY, processed_at timestamptz DEFAULT now());
CREATE TABLE notifications (id bigserial PRIMARY KEY, order_id text, note text);
SQL
run "$K kafka-topics.sh $BS --create --if-not-exists --topic $TOPIC --partitions 1 --replication-factor 1"
pause

step "Atomic dual-write via the OUTBOX" "business row + event committed in ONE transaction"
note "If the transaction aborts, NEITHER the order nor its event exists — there is"
note "no window where the DB committed but the event was lost (the dual-write bug)."
$PSQL -q <<'SQL'
BEGIN; INSERT INTO orders VALUES ('order-1','widget',100); INSERT INTO outbox_messages(event_id,order_id,payload) VALUES ('evt-1','order-1','order-1:widget:100'); COMMIT;
BEGIN; INSERT INTO orders VALUES ('order-2','gadget',250); INSERT INTO outbox_messages(event_id,order_id,payload) VALUES ('evt-2','order-2','order-2:gadget:250'); COMMIT;
BEGIN; INSERT INTO orders VALUES ('order-3','gizmo', 75); INSERT INTO outbox_messages(event_id,order_id,payload) VALUES ('evt-3','order-3','order-3:gizmo:75');  COMMIT;
SQL
note "orders=$(count 'SELECT count(*) FROM orders')  unpublished outbox=$(count 'SELECT count(*) FROM outbox_messages WHERE NOT published')"
pause

step "Relay the outbox to Kafka" "publish unpublished events, THEN mark them published"
run "$PSQL -tA -c \"SELECT event_id||'|'||payload FROM outbox_messages WHERE NOT published ORDER BY event_id\" | $K kafka-console-producer.sh $BS --topic $TOPIC"
$PSQL -q -c "UPDATE outbox_messages SET published=true WHERE NOT published" </dev/null
note "unpublished outbox now=$(count 'SELECT count(*) FROM outbox_messages WHERE NOT published'). The relay is the only thing that talks to Kafka."
pause

step "Consume + dedup (first delivery)" "each NEW event fires its side effect once"
consume_with_dedup analytics
note "notifications=$(count 'SELECT count(*) FROM notifications')  (one per order)"
pause

step "REPLAY the log (simulate at-least-once redelivery)" "a NEW group re-reads every event from offset 0"
note "Kafka kept the log, so 'audit' sees all 3 events AGAIN — the duplicates a"
note "retry or rebalance would cause. Watch the dedup absorb them:"
consume_with_dedup audit
note "notifications STILL=$(count 'SELECT count(*) FROM notifications')  — processed-once, not doubled."
pause

step "Why it holds" "idempotency key (event_id) + outbox = effectively-once"
note "processed rows=$(count 'SELECT count(*) FROM processed_events'), notifications=$(count 'SELECT count(*) FROM notifications'):"
note "every event was DELIVERED twice but PROCESSED once. That is exactly-once"
note "*processing* on top of at-least-once *delivery*."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
