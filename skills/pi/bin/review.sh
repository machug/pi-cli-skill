#!/usr/bin/env bash
# /pi review [--base <branch>] [--model <id>] — diff review via pi --mode json.
# Pure shell — no SDK, no node_modules. Requires: pi, git, jq.
set -euo pipefail

BASE=""
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base)  BASE="$2";  shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
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
  echo "No diff against ${BASE_BR}. Nothing to review." >&2
  exit 0
fi

CAP=200000
if [ "${#DIFF}" -gt "$CAP" ]; then
  DIFF="${DIFF:0:$CAP}

[diff truncated at ${CAP} bytes; ${FILES_COUNT} files total]"
fi

read -r -d '' PROMPT <<EOF || true
You are reviewing a git diff. You are an independent reviewer — your job is to
find real problems, not to agree with the author.

Diff stat:
${STAT}

Diff:
\`\`\`diff
${DIFF}
\`\`\`

Produce findings in this exact format:

[SEVERITY] file:line — description. fix.

Severities: BLOCKER, MAJOR, MINOR, NIT.

Focus on: correctness bugs, race conditions, error handling gaps, security
issues (injection, auth bypass, unsafe deserialization), API contract breaks,
test coverage gaps for new behavior. Skip style nits unless they affect
meaning.

After all findings, emit a final line with EXACTLY this format on its own line:

PI_REVIEW_GATE: {"verdict":"pass","findings":N} OR PI_REVIEW_GATE: {"verdict":"fail","findings":N,"blockers":B,"majors":M}

verdict=fail iff there is at least one BLOCKER or MAJOR. Otherwise pass.
EOF

echo "[pi-skill] mode=review base=${BASE_BR} files=${FILES_COUNT}${MODEL:+ model=${MODEL}}" >&2

PI_ARGS=(-p --mode json)
[ -n "$MODEL" ] && PI_ARGS+=(--model "$MODEL")
PI_ARGS+=("$PROMPT")

EVENTS=$(mktemp -t pi-review.XXXXXX)
trap 'rm -f "$EVENTS"' EXIT

# Pi writes diagnostics to stderr; merge so we capture errors too.
pi "${PI_ARGS[@]}" >"$EVENTS" 2>&1 || true

# Print assistant text
jq -r '
  select(.type == "agent_end") |
  .messages[] | select(.role == "assistant") |
  .content[]? | select(.type == "text") | .text
' "$EVENTS"

# Surface any provider/transport error captured in agent_end
ERR=$(jq -r '
  select(.type == "agent_end") |
  .messages[] | select(.role == "assistant") |
  .errorMessage // empty
' "$EVENTS")

if [ -n "$ERR" ]; then
  echo "" >&2
  echo "[pi-skill error] $ERR" >&2
  exit 1
fi
