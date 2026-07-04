#!/usr/bin/env bash
# �� Distributed transactions & sagas. There is no cross-service
# BEGIN…COMMIT, so a multi-service write (reserve inventory -> charge payment ->
# create shipment) is run as a SAGA: a chain of LOCAL transactions, each in its
# own table ("service"). If a later step fails, the orchestrator runs
# COMPENSATING actions to semantically undo the earlier steps. We then show an
# idempotent retry (a redelivered step does not double-apply). Pure Postgres
# (base, always-on) — the saga logic is the lesson, not the transport. Pausable.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile sagas"
PSQL="$COMPOSE exec -T -e PGPASSWORD=app postgres-primary psql -U app -d app"

count() { $PSQL -tA -c "$1" </dev/null | tr -d '[:space:]'; }
row()   { $PSQL -tA -c "$1" </dev/null; }

# --- Saga steps. Each is a LOCAL transaction against one "service" table. -----
# Every step is idempotent: it claims an idempotency key in saga_processed first,
# and a redelivered step is a no-op. Steps echo OK / FAIL so the orchestrator can
# decide whether to proceed or compensate.

reserve_inventory() {  # order_id sku qty
  local oid="$1" sku="$2" qty="$3" claimed left
  claimed=$(count "WITH ins AS (INSERT INTO saga_processed(step_key) VALUES ('reserve:$oid') ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*) FROM ins")
  if [ "$claimed" != "1" ]; then echo "    reserve($oid): already applied — skip (idempotent)"; echo OK; return; fi
  # Wrap the conditional UPDATE in a CTE + SELECT so we read back ONLY the new
  # stock value — a bare "UPDATE … RETURNING" also prints the "UPDATE 1" tag.
  left=$(count "WITH u AS (UPDATE saga_inventory SET available = available - $qty WHERE sku='$sku' AND available >= $qty RETURNING available) SELECT available FROM u")
  if [ -z "$left" ]; then
    $PSQL -q -c "DELETE FROM saga_processed WHERE step_key='reserve:$oid'" </dev/null
    echo "    reserve($oid): FAIL — out of stock"; echo FAIL; return
  fi
  $PSQL -q -c "INSERT INTO saga_log(order_id,step,status) VALUES ('$oid','reserve','done')" </dev/null
  echo "    reserve($oid): -$qty $sku  (stock now $left)"; echo OK
}

charge_payment() {  # order_id amount
  local oid="$1" amt="$2" claimed
  claimed=$(count "WITH ins AS (INSERT INTO saga_processed(step_key) VALUES ('charge:$oid') ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*) FROM ins")
  if [ "$claimed" != "1" ]; then echo "    charge($oid): already applied — skip (idempotent)"; echo OK; return; fi
  $PSQL -q -c "INSERT INTO saga_payments(order_id,amount,state) VALUES ('$oid',$amt,'authorized')" </dev/null
  $PSQL -q -c "INSERT INTO saga_log(order_id,step,status) VALUES ('$oid','charge','done')" </dev/null
  echo "    charge($oid): authorized \$$amt"; echo OK
}

create_shipment() {  # order_id region
  local oid="$1" region="$2" claimed
  # A restricted region has no carrier — this is the step we force to fail.
  if [ "$region" = "restricted" ]; then echo "    ship($oid): FAIL — no carrier serves '$region'"; echo FAIL; return; fi
  claimed=$(count "WITH ins AS (INSERT INTO saga_processed(step_key) VALUES ('ship:$oid') ON CONFLICT DO NOTHING RETURNING 1) SELECT count(*) FROM ins")
  if [ "$claimed" != "1" ]; then echo "    ship($oid): already applied — skip (idempotent)"; echo OK; return; fi
  $PSQL -q -c "INSERT INTO saga_shipments(order_id,state) VALUES ('$oid','created')" </dev/null
  $PSQL -q -c "INSERT INTO saga_log(order_id,step,status) VALUES ('$oid','ship','done')" </dev/null
  echo "    ship($oid): shipment created"; echo OK
}

# --- Compensations: semantic undo, run in REVERSE order of completed steps. ---
comp_shipment() { # order_id
  $PSQL -q -c "UPDATE saga_shipments SET state='cancelled' WHERE order_id='$1' AND state='created'" </dev/null
  $PSQL -q -c "INSERT INTO saga_log(order_id,step,status) VALUES ('$1','ship','compensated')" </dev/null
  echo "    comp ship($1): shipment cancelled"
}
comp_payment() { # order_id
  $PSQL -q -c "UPDATE saga_payments SET state='refunded' WHERE order_id='$1' AND state='authorized'" </dev/null
  $PSQL -q -c "INSERT INTO saga_log(order_id,step,status) VALUES ('$1','charge','compensated')" </dev/null
  echo "    comp charge($1): payment refunded"
}
comp_inventory() { # order_id sku qty
  $PSQL -q -c "UPDATE saga_inventory SET available = available + $3 WHERE sku='$2'" </dev/null
  $PSQL -q -c "INSERT INTO saga_log(order_id,step,status) VALUES ('$1','reserve','compensated')" </dev/null
  echo "    comp reserve($1): +$3 $2 returned to stock"
}

# Run the saga for one order. The orchestrator advances step by step and, on the
# first failure, compensates exactly the steps that completed, in reverse. Each
# step prints its human line(s) then a final OK/FAIL verdict line, which we split
# off to decide whether to proceed or unwind.
run_saga() { # order_id sku qty amount region
  local oid="$1" sku="$2" qty="$3" amt="$4" region="$5" r
  r=$(reserve_inventory "$oid" "$sku" "$qty"); echo "${r%$'\n'*}"
  [ "${r##*$'\n'}" = "OK" ] || return 1
  r=$(charge_payment "$oid" "$amt"); echo "${r%$'\n'*}"
  if [ "${r##*$'\n'}" != "OK" ]; then comp_inventory "$oid" "$sku" "$qty"; return 1; fi
  r=$(create_shipment "$oid" "$region"); echo "${r%$'\n'*}"
  if [ "${r##*$'\n'}" != "OK" ]; then
    note "step 3 failed -> compensating completed steps in reverse"
    comp_payment "$oid"
    comp_inventory "$oid" "$sku" "$qty"
    return 1
  fi
  return 0
}

echo "${BOLD}�� Distributed transactions & sagas${RESET}"
note "Assumes 'make sagas' is running (base Postgres; the saga logic is the point)."

step "Set up the per-service tables" "inventory, payments, shipments, saga_log, processed (idempotency)"
$PSQL -q <<'SQL'
DROP TABLE IF EXISTS saga_inventory, saga_payments, saga_shipments, saga_log, saga_processed;
CREATE TABLE saga_inventory (sku text PRIMARY KEY, available int);
CREATE TABLE saga_payments  (order_id text PRIMARY KEY, amount int, state text);
CREATE TABLE saga_shipments (order_id text PRIMARY KEY, state text);
CREATE TABLE saga_log  (id bigserial PRIMARY KEY, order_id text, step text, status text, at timestamptz DEFAULT now());
CREATE TABLE saga_processed (step_key text PRIMARY KEY);
INSERT INTO saga_inventory VALUES ('widget', 5);
SQL
note "starting stock: widget=$(count "SELECT available FROM saga_inventory WHERE sku='widget'")"
pause

step "Happy path — order-1 completes all three local transactions" "each service commits its own step in order"
run_saga order-1 widget 1 100 domestic || true
note "stock=$(count "SELECT available FROM saga_inventory WHERE sku='widget'")  payments=$(count 'SELECT count(*) FROM saga_payments')  shipments=$(count 'SELECT count(*) FROM saga_shipments')"
pause

step "Partial failure — order-2 fails at shipping, saga unwinds" "reserve + charge commit, ship fails, compensations fire in reverse"
note "order-2 ships to a 'restricted' region with no carrier — step 3 will fail."
run_saga order-2 widget 2 250 restricted || true
note "After compensation the world is back to a consistent state:"
note "stock=$(count "SELECT available FROM saga_inventory WHERE sku='widget'")  (the 2 reserved units were returned)"
note "payments authorized=$(count "SELECT count(*) FROM saga_payments WHERE state='authorized'")  refunded=$(count "SELECT count(*) FROM saga_payments WHERE state='refunded'")"
pause

step "Idempotent retry — replay order-1's reserve step" "a redelivered message must NOT double-apply"
note "Imagine the broker redelivers order-1's 'reserve' (at-least-once). Re-run it:"
r=$(reserve_inventory order-1 widget 1); echo "${r%$'\n'*}"
note "stock STILL=$(count "SELECT available FROM saga_inventory WHERE sku='widget'")  — the idempotency key absorbed the duplicate."
pause

step "Audit the saga log" "every step's outcome, including compensations"
run "$PSQL -c \"SELECT order_id, step, status FROM saga_log ORDER BY id\""
note "order-1: three 'done' rows. order-2: 'done' for reserve+charge, then both 'compensated'."
note "No global transaction, yet no money charged without a shipment and no stock leaked."

echo
echo "${BOLD}Done.${RESET} Cleanup: ${GREEN}make reset${RESET}"
