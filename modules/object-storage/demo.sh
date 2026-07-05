#!/usr/bin/env bash
# Object storage. Large binary blobs do not belong in Postgres rows.
# They go to an object store (MinIO, S3-compatible) and are handed to clients via
# time-limited presigned URLs so bytes never flow through the app.
set -uo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"

COMPOSE="docker compose --profile object-storage"
NET="systems-design_backend"                 # backend network the app + minio share
MC_IMAGE="minio/mc:RELEASE.2024-06-12T14-34-03Z"
MINIO_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_PASS="${MINIO_ROOT_PASSWORD:-minioadmin}"
BUCKET="blobs"

# mc client, run as a throwaway container on the backend network. MC_HOST_local
# configures the "local" alias (endpoint + credentials) with no extra step.
MC() {
  docker run --rm -i --network "$NET" \
    -e "MC_HOST_local=http://${MINIO_USER}:${MINIO_PASS}@minio:9000" \
    "$MC_IMAGE" "$@"
}

# wget from the app container — an UNPRIVILEGED client on the backend network,
# holding no MinIO credentials. Proves a presigned URL is self-authorising.
app_get() { $COMPOSE exec -T app sh -c "wget -qO- '$1' 2>&1 || true"; }

echo "${BOLD}Object storage${RESET}"
note "Assumes 'make object-storage' is running (base + MinIO)."

step "Wait for the object store to be ready" "MinIO answers its health probe before we use it"
until MC ready local >/dev/null 2>&1; do sleep 1; done
note "MinIO is ready (console: http://localhost:${MINIO_CONSOLE_PORT:-9101}, user/pass: ${MINIO_USER}/${MINIO_PASS})"
pause

step "Create a private bucket" "a flat namespace of buckets/keys — not a filesystem, not a table"
MC rb --force "local/$BUCKET" >/dev/null 2>&1 || true   # idempotent across re-runs
run "MC mb local/$BUCKET"
pause

step "Store blobs as objects" "large/opaque bytes live OUTSIDE the database"
echo "quarterly numbers, revenue up and to the right" | MC pipe "local/$BUCKET/report.txt" >/dev/null
head -c 262144 /dev/urandom | MC pipe "local/$BUCKET/backup.bin" >/dev/null
echo "meeting notes: ship object storage, then sleep" | MC pipe "local/$BUCKET/notes.txt" >/dev/null
run "MC ls --recursive local/$BUCKET"
note "flat key namespace, byte sizes tracked by the store — the DB never sees these bytes"
pause

step "Read an object straight back out" "the store is the source of truth for the bytes"
run "MC cat local/$BUCKET/report.txt"
pause

step "The bucket is private: an unsigned request is refused" "no credentials, no signature -> no access"
note "app container fetches http://minio:9000/$BUCKET/report.txt with NO signature:"
app_get "http://minio:9000/$BUCKET/report.txt"
note "^ refused — objects are not world-readable by default"
pause

step "Presigned URL: grant time-limited, credential-free access" "the client reads directly from the store, off the app's critical path"
URL=$(MC share download "local/$BUCKET/report.txt" --expire=3m 2>/dev/null | awk '/^Share:/{print $2}')
note "generated a signed URL valid for 3 minutes:"
echo "  ${DIM}${URL}${RESET}"
note "the app container (still no credentials) fetches THAT url:"
run "app_get \"\$URL\""
note "bytes flowed minio -> client directly; the app only handed over a URL"
pause

step "Scope note" "what a production build adds on top of this"
cat <<EOF
  ${DIM}This lab stands up the object store (MinIO).
  A production system would also:
    • serve blobs through a CDN with MinIO as the ORIGIN  -> see edge caching (edge caching)
    • use multipart/resumable uploads for very large objects (mc does this transparently)
    • store object metadata, ownership, and permissions in the database
  These are documented in the README but not stood up, to keep the profile small.${RESET}
EOF

echo
echo "${BOLD}${GREEN}Done.${RESET} Blobs live in the object store and are served via presigned URLs;"
echo "the app authorizes access without proxying object bytes."
note "Clean up with: make reset"
