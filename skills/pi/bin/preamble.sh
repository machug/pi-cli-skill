#!/usr/bin/env bash
# Preamble for /pi: sanity-check pi + jq, refresh model cache, report status.
set -e

if ! command -v pi >/dev/null 2>&1; then
  echo "pi CLI not found. Install: npm install -g @mariozechner/pi-coding-agent"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found. Install with your package manager (apt/brew/pacman install jq)."
  exit 1
fi

# Pi writes diagnostics to stderr — keep 2>&1 to capture
PI_VERSION=$(pi --version 2>&1 | head -1)
echo "PI_VERSION: $PI_VERSION"
echo "JQ: $(jq --version)"

BRANCH=$(git branch --show-current 2>/dev/null || echo "(no git)")
echo "BRANCH: $BRANCH"

CACHE_DIR="$HOME/.cache/pi-cli-skill"
mkdir -p "$CACHE_DIR"
MODELS_CACHE="$CACHE_DIR/models.txt"
if [ ! -f "$MODELS_CACHE" ] || [ "$(find "$MODELS_CACHE" -mmin +1440 2>/dev/null | wc -l)" -gt 0 ]; then
  pi --list-models > "$MODELS_CACHE" 2>&1 || true
fi
MODEL_COUNT=$(wc -l < "$MODELS_CACHE" 2>/dev/null | tr -d ' ')
FOUNDRY_COUNT=$(grep -c '^foundry-' "$MODELS_CACHE" 2>/dev/null || echo 0)
echo "MODELS: $MODEL_COUNT lines, $FOUNDRY_COUNT foundry-hosted"
