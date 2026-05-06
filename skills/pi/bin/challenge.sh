#!/usr/bin/env bash
# /pi challenge [--rounds N] [--model <id>] — adversarial multi-turn loop.
# Pure shell — no SDK, no node_modules. Requires: pi, git, jq.
set -euo pipefail

ROUNDS=3
MODEL=""
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rounds) ROUNDS="$2"; shift 2 ;;
    --model)  MODEL="$2";  shift 2 ;;
    --base)   BASE="$2";   shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

detect_base() {
  if [ -n "$BASE" ] && [ "$BASE" != "auto" ]; then echo "$BASE"; return; fi
  local b
  b=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null | sed 's,^origin/,,' || true)
  if [ -n "$b" ]; then echo "$b"; return; fi
  b=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's,^refs/remotes/origin/,,' || true)
  if [ -n "$b" ]; then echo "$b"; return; fi
  for cand in master main; do
    if git rev-parse --verify "$cand" >/dev/null 2>&1; then echo "$cand"; return; fi
  done
  return 1
}

BASE_BR=$(detect_base) || { echo "Could not detect base branch. Pass --base <name>." >&2; exit 3; }

STAT=$(git diff --stat "${BASE_BR}...HEAD" || true)
DIFF=$(git diff "${BASE_BR}...HEAD" || true)
FILES_COUNT=$(git diff --name-only "${BASE_BR}...HEAD" 2>/dev/null | grep -c . || true)

if [ -z "$DIFF" ]; then
  echo "No diff against ${BASE_BR}. Nothing to challenge." >&2
  exit 0
fi

CAP=200000
if [ "${#DIFF}" -gt "$CAP" ]; then
  DIFF="${DIFF:0:$CAP}

[diff truncated at ${CAP} bytes; ${FILES_COUNT} files total]"
fi

read -r -d '' INITIAL <<EOF || true
You are an adversarial reviewer. Your goal is to BREAK the code in this diff.
Find inputs, sequences, environments, or assumptions that make it fail.

Diff stat:
${STAT}

Diff:
\`\`\`diff
${DIFF}
\`\`\`

For round 1, identify the 3-5 most likely failure modes. Be concrete: name the
exact input or sequence. Severity-tag each (BLOCKER / MAJOR / MINOR).

Format:
[SEVERITY] vector — concrete failure scenario. why it breaks. how to verify.
EOF

ANGLES=(
  "Now focus on concurrency and race conditions specifically. Where can two requests, two writers, or two state transitions interleave to produce a corrupt state?"
  "Now focus on error and partial-failure paths. What happens if the network call mid-way through this code times out? If the disk write fails? If a downstream service returns an unexpected shape?"
  "Now focus on security. Auth bypass, injection (SQL/command/prompt/path), unsafe deserialization, secrets leaking into logs, TOCTOU. Be specific about the input that triggers it."
  "Now focus on the boundary conditions: empty input, null/undefined, max-size input, unicode edge cases, time/timezone, leap seconds, integer overflow. Pick the one most likely to actually hit prod."
)

SUMMARY='Now produce a deduplicated, severity-sorted summary of all the breakages you found across rounds. One line each: [SEVERITY] vector — scenario. fix priority. End with: PI_CHALLENGE_GATE: {"breakages":N,"blockers":B,"majors":M}'

SESSION_ID=""
EVENTS=$(mktemp -t pi-challenge.XXXXXX)
trap 'rm -f "$EVENTS"' EXIT

# run_pi_round <prompt> [extra pi flags...]
# Captures session id from round 1; prints assistant text; aborts on errorMessage.
run_pi_round() {
  local prompt="$1"; shift
  local args=(-p --mode json)
  [ -n "$MODEL" ] && args+=(--model "$MODEL")
  if [ -n "$SESSION_ID" ]; then
    args+=(--session "$SESSION_ID")
  fi
  args+=("$@" "$prompt")

  : > "$EVENTS"
  pi "${args[@]}" >"$EVENTS" 2>&1 || true

  if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(jq -r 'select(.type=="session") | .id' "$EVENTS" | head -1)
  fi

  jq -r '
    select(.type == "agent_end") |
    .messages[] | select(.role == "assistant") |
    .content[]? | select(.type == "text") | .text
  ' "$EVENTS"

  local err
  err=$(jq -r '
    select(.type == "agent_end") |
    .messages[] | select(.role == "assistant") |
    .errorMessage // empty
  ' "$EVENTS")
  if [ -n "$err" ]; then
    echo "" >&2
    echo "[pi-skill error] $err" >&2
    exit 1
  fi
}

echo "[pi-skill] mode=challenge base=${BASE_BR} files=${FILES_COUNT} rounds=${ROUNDS}${MODEL:+ model=${MODEL}}" >&2

echo "" >&2
echo "[pi-skill] --- challenge round 1/${ROUNDS} ---" >&2
echo "" >&2
run_pi_round "$INITIAL"

if [ -z "$SESSION_ID" ]; then
  echo "[pi-skill] failed to capture session id from pi output; cannot continue multi-round." >&2
  exit 1
fi

for ((round=2; round <= ROUNDS; round++)); do
  angle_idx=$(( (round - 2) % ${#ANGLES[@]} ))
  echo "" >&2
  echo "[pi-skill] --- challenge round ${round}/${ROUNDS} ---" >&2
  echo "" >&2
  run_pi_round "${ANGLES[$angle_idx]}"
done

echo "" >&2
echo "[pi-skill] --- final summary ---" >&2
echo "" >&2
run_pi_round "$SUMMARY"
