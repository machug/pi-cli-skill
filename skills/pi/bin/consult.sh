#!/usr/bin/env bash
# /pi consult <question> — one-shot ask, session-resumable next call via /pi resume.
# Usage: consult.sh [--model <id>] [--continue] -- <prompt>
set -e

MODEL=""
CONTINUE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --continue|-c) CONTINUE="-c"; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

PROMPT="$*"
if [ -z "$PROMPT" ]; then
  echo "Usage: consult.sh [--model <id>] [--continue] -- <prompt>" >&2
  exit 2
fi

CMD=(pi -p $CONTINUE)
[ -n "$MODEL" ] && CMD+=(--model "$MODEL")
CMD+=("$PROMPT")

exec "${CMD[@]}"
