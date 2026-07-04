#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <module> [module ...]" >&2
  exit 2
fi

passes=0
failures=0
failed_modules=()

run_step() {
  local label="$1"
  shift
  echo
  echo "==> $label"
  "$@"
}

validate_module() {
  local module="$1"
  local demo="modules/$module/demo.sh"

  echo
  echo "============================================================"
  echo "Validating $module"
  echo "============================================================"

  if [ ! -x "$demo" ]; then
    echo "FAIL: $demo is missing or not executable" >&2
    return 1
  fi

  run_step "reset before $module" make reset || return 1
  run_step "start $module" make "$module" || return 1
  run_step "wait for gateway health" wait_for_gateway || return 1
  run_step "run $demo" env AUTO=1 "$demo" || return 1
  run_step "reset after $module" make reset || return 1
}

wait_for_gateway() {
  local url="http://localhost:${GATEWAY_HTTP_PORT:-8080}/health"
  local code=""

  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [ "$code" = "200" ]; then
      curl -fsS "$url"
      printf '\n'
      return 0
    fi
    sleep 2
  done

  echo "FAIL: gateway health did not become ready at $url" >&2
  return 1
}

for module in "$@"; do
  if validate_module "$module"; then
    passes=$((passes + 1))
    echo "PASS: $module"
  else
    failures=$((failures + 1))
    failed_modules+=("$module")
    echo "FAIL: $module" >&2
    make reset || true
  fi
done

echo
echo "============================================================"
echo "Validation summary"
echo "============================================================"
echo "Passed: $passes"
echo "Failed: $failures"

if [ "$failures" -ne 0 ]; then
  printf 'Failed modules:' >&2
  printf ' %s' "${failed_modules[@]}" >&2
  printf '\n' >&2
  exit 1
fi
