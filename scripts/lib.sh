#!/usr/bin/env bash
# Shared helpers for module demo.sh scripts (§10 demo.sh format).
# Source this at the top of a demo:
#   source "$(dirname "$0")/../../scripts/lib.sh"
#
# Provides: step, explain, observe, expect, meaning, pause, predict, checkpoint,
# try_it, run, note, and the GATEWAY/COMPOSE convenience vars.

set -uo pipefail

# Colors (disabled if not a TTY).
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

# Repo root (two levels up from modules/<slug>/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY="${GATEWAY:-http://localhost:${GATEWAY_HTTP_PORT:-8080}}"
COMPOSE="${COMPOSE:-docker compose}"

_STEP=0

# step "Concept" "what to observe"
step() {
  _STEP=$((_STEP + 1))
  echo
  echo "${BOLD}${CYAN}── Step ${_STEP}: $1${RESET}"
  if [ "${2:-}" != "" ]; then
    echo "${DIM}   Observe: $2${RESET}"
  fi
}

# note "message"
note() { echo "${YELLOW}» $*${RESET}"; }

# explain / observe / expect / meaning print the self-study layer of a lab step.
explain() { echo "${DIM}   Why: $*${RESET}"; }
observe() { echo "${DIM}   Observe: $*${RESET}"; }
expect() { echo "${DIM}   Expected: $*${RESET}"; }
meaning() { echo "${DIM}   Meaning: $*${RESET}"; }

# predict "question" [answer] — ask for a hypothesis before showing the result.
predict() {
  echo "${YELLOW}? Predict:${RESET} $1"
  if [ "${AUTO:-0}" != "1" ]; then
    read -r -p "${DIM}write your prediction, then press Enter… ${RESET}" _ </dev/tty || true
  fi
  if [ "${2:-}" != "" ]; then
    echo "${DIM}   Check against: $2${RESET}"
  fi
}

# checkpoint "question" [answer] — pause for a short self-check after output.
checkpoint() {
  echo "${YELLOW}? Checkpoint:${RESET} $1"
  if [ "${AUTO:-0}" != "1" ]; then
    read -r -p "${DIM}answer in your notes, then press Enter to reveal… ${RESET}" _ </dev/tty || true
  fi
  if [ "${2:-}" != "" ]; then
    echo "${DIM}   One good answer: $2${RESET}"
  fi
}

# try_it "task" [hint] — give a small hands-on variation before continuing.
try_it() {
  echo "${YELLOW}Try:${RESET} $1"
  if [ "${2:-}" != "" ]; then
    echo "${DIM}   Hint: $2${RESET}"
  fi
  if [ "${AUTO:-0}" != "1" ]; then
    read -r -p "${DIM}try it now, then press Enter to continue… ${RESET}" _ </dev/tty || true
  fi
}

# pause [message] — wait for the user before moving on (skipped when AUTO=1).
pause() {
  if [ "${AUTO:-0}" = "1" ]; then return 0; fi
  read -r -p "${DIM}${1:-press Enter to continue…}${RESET}" _ </dev/tty || true
}

# run "command string" — echo then execute, so the reader sees the command.
run() {
  echo "${GREEN}Command:${RESET} $*"
  eval "$@"
}
