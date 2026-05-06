---
name: pi
description: |
  Pi CLI wrapper — three modes. Review: independent diff review via Pi CLI with
  pass/fail gate. Challenge: adversarial mode that tries to break your code via
  multi-turn loop. Consult: ask Pi anything with session continuity.
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

Wraps the [Pi coding agent](https://pi.dev) CLI. Independent voice from the
session you're in — different provider, different context, fresh eyes.

> **Note for the assistant:** all logic lives in `bin/*.sh`. The skill body is
> intentionally free of inline shell positional variables (the dollar-zero
> through dollar-nine forms, plus dollar-at and dollar-star) so the
> slash-command processor cannot mangle it via positional-arg substitution.
> The skill shells out to `pi --print --mode json` and parses NDJSON with
> `jq` — no SDK, no bundled `node_modules`.

## How to invoke

The skill receives a subcommand as its first argument. Map it to the matching
script under `bin/`. The skill base directory is provided by Claude Code in the
`CLAUDE_PLUGIN_ROOT`-style preamble; the assistant should resolve `BIN` as the
absolute path to `<skill_root>/bin` and call the relevant `.sh`.

Always run `bin/preamble.sh` first to verify the environment, then dispatch.

## Subcommands

### `models`

Print discovery grouped by provider. Foundry-* providers marked with `*`.

```
bin/preamble.sh
bin/models.sh
```

### `consult <question> [--model <id>] [--continue]`

One-shot ask, session-resumable. With `--continue`, picks up the last Pi
session.

```
bin/preamble.sh
bin/consult.sh [--model "<id>"] [--continue] -- "<question>"
```

### `review [--base <branch>] [--model <id>]`

Independent diff review. Detects base branch automatically (upstream →
origin/HEAD → master → main). Prints findings tagged
`[BLOCKER|MAJOR|MINOR|NIT]` and emits a final `PI_REVIEW_GATE: {...}` JSON
verdict.

```
bin/preamble.sh
bin/review.sh [--base "<branch>"] [--model "<id>"]
```

After the run completes, parse the last `PI_REVIEW_GATE:` line. If
`verdict=="fail"`, surface the findings to the user. Do not auto-fix unless
the user asks.

### `challenge [--rounds N] [--model <id>]`

Adversarial multi-turn loop. Pi tries to break the diff — concurrency, error
paths, security, boundary conditions. Default 3 rounds.

```
bin/preamble.sh
bin/challenge.sh [--rounds N] [--model "<id>"]
```

Final summary line: `PI_CHALLENGE_GATE: {"breakages":N,"blockers":B,"majors":M}`.

### `resume [<prompt>]`

Continue last Pi session. No args = interactive. With args = one-shot
continue.

```
bin/resume.sh ["<prompt>"]
```

## Defaults

- **Model**: none hardcoded. Pi uses its own configured default. Override per
  call with `--model "<provider>/<modelId>"`.
- **Session storage**: Pi's default. Skill does not manage it.

## Auth

Skill assumes Pi is already authenticated. First-run setup is Pi's
responsibility — if `pi --list-models` errors or returns nothing, tell the user
to run `pi` once interactively to log in / configure providers.

## Why use this

- **Independent voice**: Pi runs a different model than the current session
  — real second opinion, not the same model agreeing with itself.
- **Foundry-friendly**: surfaces Azure AI Foundry-hosted models (`foundry-*`)
  alongside others. Routes through your Foundry tenant if you pick one.
- **Adversarial loop**: keeps a single Pi session across challenge rounds via
  `pi --session <id>` so each round builds on the prior context.
- **No bundled deps**: pure shell-out to `pi`. Nothing to `bun install`,
  nothing to keep in lockstep with upstream pi versions.

## Implementation notes (for maintainers)

- Pi writes diagnostics (`--version`, `--list-models`) to stderr, not stdout.
  Capture with `2>&1`.
- Slash command processors textually substitute shell positional variables
  (the dollar-N forms, plus dollar-at and dollar-star) in the rendered skill
  body. Keep all dollar-using shell logic in `bin/*.sh` files. (Even quoting
  them in backticks is not safe — substitution happens before render.)
- Review/challenge use `pi -p --mode json` and extract assistant text from the
  `agent_end` event with `jq`. Errors surface via the same event's
  `errorMessage` field.
- Challenge resumes via `pi --session <id>`; the id is captured from the
  first round's `session` event.
