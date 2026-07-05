#!/usr/bin/env bash
# Databases demonstration.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="${COMPOSE:-docker compose}"
PSQL="$COMPOSE exec -T postgres-primary psql -U app -d app"

echo "${BOLD}Module - Databases${RESET}"
note "Assumes 'make base' is running. This module uses the base Postgres database."
note "Loop: inspect schema, write rows, read rows, and explain what the database protects."

step "Find the database table" \
     "a database schema is the structure the app relies on"
predict "What table should a URL shortener need at minimum?" \
        "A table that maps a short code to the original URL. In this lab it is named links."
run "$PSQL -c '\\dt'"
run "$PSQL -c '\\d links'"
checkpoint "What does the primary key protect?" \
           "It makes each code unique, so two different URLs cannot claim the same short code."
pause

step "Insert and read a row" \
     "writes create durable state; reads retrieve it later"
predict "After inserting a row, what should a SELECT by code return?" \
        "It should return the URL stored for that code."
run "$PSQL -c \"INSERT INTO links (code, url) VALUES ('dbdemo', 'https://example.com/database') ON CONFLICT (code) DO UPDATE SET url = EXCLUDED.url;\""
run "$PSQL -c \"SELECT code, url FROM links WHERE code = 'dbdemo';\""
checkpoint "Why is this different from storing data inside one app replica's memory?" \
           "The row lives in Postgres, so any app replica can read it and it survives app restarts."
pause

step "Look at the query path" \
     "indexes help the database find rows without checking every row"
predict "Which column should be fast to search for in a redirect path?" \
        "The short code, because redirects start with a code and need the target URL."
run "$PSQL -c \"SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'links';\""
run "$PSQL -c \"SET enable_seqscan = off; EXPLAIN SELECT code, url FROM links WHERE code = 'dbdemo';\""
checkpoint "Why does the primary-key index matter for this system?" \
           "Redirects are point lookups by code; an index keeps that lookup fast as the table grows."
pause

step "Rollback a transaction" \
     "a transaction can group changes and undo them before commit"
predict "If a row is inserted inside a transaction and then rolled back, should it remain?" \
        "No. ROLLBACK discards the uncommitted change."
run "$PSQL -c \"BEGIN; INSERT INTO links (code, url) VALUES ('dbdemo_rollback', 'https://example.com/rollback') ON CONFLICT DO NOTHING; SELECT code, url FROM links WHERE code = 'dbdemo_rollback'; ROLLBACK;\""
run "$PSQL -c \"SELECT count(*) AS rows_after_rollback FROM links WHERE code = 'dbdemo_rollback';\""
checkpoint "What does rollback protect you from assuming?" \
           "Not every attempted write becomes durable; the database only keeps changes that commit."
pause

step "Connect this to system design" \
     "database choices shape later scaling decisions"
try_it "Name one later mechanism that exists because databases have limits." \
       "Examples: replication for read capacity/failover, sharding for write/storage capacity, caching for hot reads, queues for bursts."
checkpoint "What should you understand before choosing replication or sharding?" \
           "The data model, access pattern, read/write volume, consistency needs, and current bottleneck."

run "$PSQL -c \"DELETE FROM links WHERE code IN ('dbdemo', 'dbdemo_rollback');\""

echo
nnote="${BOLD}Done.${RESET} Next: replication and failover shows what changes when the database has a standby."
note "$nnote"
