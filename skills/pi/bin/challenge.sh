#!/usr/bin/env bash
# /pi challenge [--rounds N] [--model <id>] — adversarial multi-turn loop via SDK.
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SKILL_DIR"

if [ ! -d node_modules ]; then
  echo "[pi-skill] installing runner deps (one-time)..." >&2
  bun install >&2
fi

exec bun run runner.ts challenge "$@"
