---
name: pi
description: |
  Pi CLI wrapper — three modes. Review: independent diff review via Pi SDK with
  pass/fail gate. Challenge: adversarial mode that tries to break your code via
  multi-turn steer() loop. Consult: ask Pi anything with session continuity.
  Provider-agnostic second opinion (Foundry, Anthropic, OpenAI, HuggingFace,
  whatever Pi has configured). Use when asked to "pi review", "pi challenge",
  "ask pi", "consult pi", or "second opinion via pi".
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Pi skill

Wraps the [Pi coding agent](https://pi.dev) CLI + SDK. Independent voice from the
session you're in — different provider, different context, fresh eyes.

## Preamble (run first)

```bash
set -e
SKILL_DIR="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")}/skills/pi"
[ ! -d "$SKILL_DIR" ] && SKILL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"

# Pi installed?
if ! command -v pi >/dev/null 2>&1; then
  echo "pi CLI not found. Install: npm install -g @mariozechner/pi-coding-agent"
  exit 1
fi

# Pi writes to stderr, not stdout — keep 2>&1
PI_VERSION=$(pi --version 2>&1 | head -1)
echo "PI_VERSION: $PI_VERSION"

# Bun installed (for SDK runner)?
if command -v bun >/dev/null 2>&1; then
  echo "BUN: $(bun --version)"
else
  echo "BUN: missing — review/challenge modes need bun. consult mode still works."
fi

# Branch context
BRANCH=$(git branch --show-current 2>/dev/null || echo "(no git)")
echo "BRANCH: $BRANCH"

# Discovery: cached model list
CACHE_DIR="$HOME/.cache/pi-cli-skill"
mkdir -p "$CACHE_DIR"
MODELS_CACHE="$CACHE_DIR/models.txt"
if [ ! -f "$MODELS_CACHE" ] || [ $(find "$MODELS_CACHE" -mmin +1440 2>/dev/null | wc -l) -gt 0 ]; then
  pi --list-models > "$MODELS_CACHE" 2>&1 || true
fi
MODEL_COUNT=$(wc -l < "$MODELS_CACHE" 2>/dev/null | tr -d ' ')
FOUNDRY_COUNT=$(grep -c '^foundry-' "$MODELS_CACHE" 2>/dev/null || echo 0)
echo "MODELS: $MODEL_COUNT total, $FOUNDRY_COUNT foundry-hosted"

# SDK runner deps installed?
if [ ! -d "$SKILL_DIR/node_modules" ]; then
  echo "DEPS: not installed (run: cd $SKILL_DIR && bun install)"
else
  echo "DEPS: installed"
fi
```

## Subcommands

User invokes `/pi <subcommand>` or types phrasings like "pi review", "ask pi X",
"have pi challenge this".

### `/pi consult <question>`

CLI passthrough. One-shot ask, session-resumable.

```bash
# First call
pi -p "<question>"
# Follow-up (continues last pi session)
pi -c -p "<follow-up question>"
```

If `--model <id>` given, append `--model <id>`.

### `/pi review [--model <id>] [--base <branch>]`

Independent diff review. Pi reads the diff against base branch (default: parent
branch detected via git, fallback `master`/`main`), produces structured findings,
and emits PASS/FAIL gate.

```bash
cd "$SKILL_DIR"
[ ! -d node_modules ] && bun install
bun run runner.ts review --base "${BASE:-auto}" ${MODEL:+--model "$MODEL"}
```

Runner outputs JSON on the last line: `{"verdict":"pass"|"fail","findings":[...]}`.

If FAIL: relay findings to user, do NOT auto-fix unless asked.

### `/pi challenge [--model <id>] [--rounds N]`

Adversarial mode. Pi tries to break your latest changes — edge cases, race
conditions, security holes, hidden assumptions. Multi-turn loop using SDK
`steer()` to keep pressing.

```bash
cd "$SKILL_DIR"
[ ! -d node_modules ] && bun install
bun run runner.ts challenge --rounds "${ROUNDS:-3}" ${MODEL:+--model "$MODEL"}
```

Runner streams each round's findings. Final output: list of breakages found, with
severity tags.

### `/pi models`

Print discovery grouped by provider. Highlight foundry-* if present.

```bash
CACHE="$HOME/.cache/pi-cli-skill/models.txt"
[ -f "$CACHE" ] || pi --list-models > "$CACHE" 2>&1
# Header row
head -1 "$CACHE"
echo "---"
# Group by provider, count, mark foundry-* with *
awk 'NR>1 {print $1}' "$CACHE" | sort -u | while read p; do
  count=$(grep -c "^$p " "$CACHE")
  marker=""
  [[ "$p" == foundry-* ]] && marker=" *"
  echo "$p ($count models)$marker"
done
```

To pick a specific model later: `/pi review --model <provider>/<model>` or just
`/pi review --model <pattern>` (Pi supports fuzzy matching).

### `/pi resume`

Continue last Pi session interactively (or with new prompt):

```bash
pi -c                          # interactive resume
pi -c -p "<new prompt>"        # one-shot continue
```

## Defaults

- **Model**: none hardcoded. Pi uses its own configured default. Override per
  call with `--model`.
- **Provider preference**: if `--prefer-foundry` set and no foundry-* model is
  available, warn before falling back.
- **Session storage**: Pi's default (`~/.config/pi/...`). Skill does not manage.

## Auth

Skill assumes Pi is already authenticated. First-run setup is Pi's
responsibility — if `pi --list-models` returns empty or errors, tell user to run
`pi` once interactively to log in / configure providers.

## Why use this

- **Independent voice**: Pi runs a different model than your current session,
  giving you a real second opinion (not the same model agreeing with itself).
- **Foundry-friendly**: surfaces Azure AI Foundry-hosted models alongside
  others. Pick `foundry-codex` for review if you want the same backend Codex
  uses but routed through your Foundry tenant.
- **Adversarial loop**: SDK `steer()` lets challenge mode keep pressing without
  spawning fresh sessions per round.
