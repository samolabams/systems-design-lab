#!/usr/bin/env bash
# Poll a URL until it returns 2xx/3xx or we time out. Used to gate demos on
# service readiness.
#
#   wait-for.sh http://localhost:8080/health 60
set -uo pipefail

URL="${1:?usage: wait-for.sh URL [timeout_seconds]}"
TIMEOUT="${2:-60}"

echo "waiting for $URL (up to ${TIMEOUT}s)…"
for ((i = 0; i < TIMEOUT; i++)); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || echo 000)
  if [[ "$code" =~ ^[23] ]]; then
    echo "ready ($code)"
    exit 0
  fi
  sleep 1
done

echo "timed out waiting for $URL" >&2
exit 1
