# pi-cli-skill

Claude Code skill that wraps [Pi](https://pi.dev) — a minimal terminal coding
agent — to give your session an independent second opinion.

Three modes:

- **`/pi consult <question>`** — one-shot ask, session-resumable.
- **`/pi review`** — diff review against base branch, with a PASS/FAIL gate.
- **`/pi challenge`** — adversarial multi-turn loop. Pi tries to break your
  code, pressing from different angles each round (concurrency, error paths,
  security, boundary conditions).

Plus:

- **`/pi models`** — discovery, grouped by provider, foundry-* highlighted.
- **`/pi resume`** — continue last Pi session.

## Why

Most "second opinion" workflows have you ask the same model that's already in
your session. That's not a second opinion — it's the same voice. Pi is
provider-agnostic: point it at a different backend (Foundry, Anthropic, OpenAI,
HuggingFace, etc.) and you get a real outside read.

## Requirements

- [Pi CLI](https://pi.dev) — `npm install -g @mariozechner/pi-coding-agent`
- `git` and `jq` (for `review` and `challenge` to capture the diff and parse
  pi's NDJSON output).
- Pi already authenticated with at least one provider configured. Run `pi`
  once interactively to set up; the skill assumes you're already logged in.

## Install

Via the Claude Code marketplace:

```
/plugin marketplace add machug
/plugin install pi-cli-skill@machug
```

## How review works

1. Detects base branch (upstream → origin/HEAD → master → main).
2. Captures diff (capped at 200KB).
3. Hands diff to Pi via `pi --print --mode json` with a structured-output prompt.
4. Pi emits findings tagged `[BLOCKER|MAJOR|MINOR|NIT] file:line — desc. fix.`
5. Final line: `PI_REVIEW_GATE: {"verdict":"pass"|"fail",...}`.
6. The calling Claude Code session parses the gate and surfaces findings.

## How challenge works

1. Initial prompt: "find the 3-5 most likely failure modes."
2. Then `--rounds N` (default 3) rounds resumed via `pi --session <id>`, each
   round shifting the angle (concurrency → error paths → security → boundaries).
3. Final summary: deduplicated, severity-sorted breakage list +
   `PI_CHALLENGE_GATE` line.

## Configuration

No skill config. Pi handles its own. Use `--model <id>` per invocation to pick
a specific model; otherwise Pi's configured default is used.

## License

MIT
