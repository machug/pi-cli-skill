#!/usr/bin/env bash
# /pi models — print discovery grouped by provider, foundry-* marked.
set -e

CACHE="$HOME/.cache/pi-cli-skill/models.txt"
if [ ! -f "$CACHE" ] || [ ! -s "$CACHE" ]; then
  mkdir -p "$(dirname "$CACHE")"
  pi --list-models > "$CACHE" 2>&1
fi

# Header
head -1 "$CACHE"
echo "---"

# Group by provider (column 1), count, mark foundry-* with *
awk 'NR>1 {print $1}' "$CACHE" | sort -u | while read -r p; do
  count=$(grep -c "^$p " "$CACHE")
  marker=""
  [[ "$p" == foundry-* ]] && marker=" *"
  echo "$p ($count models)$marker"
done

echo
echo "Pick a model: --model \"<provider>/<modelId>\" e.g. --model \"foundry-codex/gpt-5.3-codex\""
echo "List all models for one provider: grep '^<provider> ' $CACHE"
