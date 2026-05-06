#!/usr/bin/env bun
/**
 * Pi SDK runner for review and challenge modes.
 * SKILL.md invokes this. Not meant to be called directly by users.
 *
 * Usage:
 *   bun runner.ts review [--base <branch>] [--model <id>]
 *   bun runner.ts challenge [--rounds N] [--model <id>]
 */

import { createAgentSession, SessionManager } from "@mariozechner/pi-coding-agent";
import { getModel } from "@mariozechner/pi-ai";
import { execSync } from "node:child_process";

type Mode = "review" | "challenge";

interface Args {
  mode: Mode;
  base?: string;
  model?: string;
  rounds: number;
}

function parseArgs(argv: string[]): Args {
  const mode = argv[0] as Mode;
  if (mode !== "review" && mode !== "challenge") {
    console.error(`Unknown mode: ${mode}. Expected: review | challenge`);
    process.exit(2);
  }
  const args: Args = { mode, rounds: 3 };
  for (let i = 1; i < argv.length; i++) {
    const flag = argv[i];
    const val = argv[i + 1];
    if (flag === "--base") { args.base = val; i++; }
    else if (flag === "--model") { args.model = val; i++; }
    else if (flag === "--rounds") { args.rounds = parseInt(val, 10) || 3; i++; }
  }
  return args;
}

function sh(cmd: string): string {
  return execSync(cmd, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function detectBase(explicit?: string): string {
  if (explicit && explicit !== "auto") return explicit;
  // Try @{upstream}, then origin/HEAD, then master, then main
  const candidates = [
    () => sh("git rev-parse --abbrev-ref @{upstream}").replace(/^origin\//, ""),
    () => sh("git symbolic-ref refs/remotes/origin/HEAD").replace(/^refs\/remotes\/origin\//, ""),
    () => { sh("git rev-parse --verify master"); return "master"; },
    () => { sh("git rev-parse --verify main"); return "main"; },
  ];
  for (const fn of candidates) {
    try { const b = fn(); if (b) return b; } catch { /* keep trying */ }
  }
  console.error("Could not detect base branch. Pass --base <name>.");
  process.exit(3);
}

function getDiff(base: string): { diff: string; stat: string; files: string[] } {
  const stat = sh(`git diff --stat ${base}...HEAD`);
  const files = sh(`git diff --name-only ${base}...HEAD`).split("\n").filter(Boolean);
  let diff = sh(`git diff ${base}...HEAD`);
  // Cap at 200KB to avoid blowing the context
  const cap = 200_000;
  if (diff.length > cap) {
    diff = diff.slice(0, cap) + `\n\n[diff truncated at ${cap} bytes; ${files.length} files total]`;
  }
  return { diff, stat, files };
}

function reviewPrompt(diff: string, stat: string): string {
  return `You are reviewing a git diff. You are an independent reviewer — your job is to
find real problems, not to agree with the author.

Diff stat:
${stat}

Diff:
\`\`\`diff
${diff}
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

verdict=fail iff there is at least one BLOCKER or MAJOR. Otherwise pass.`;
}

function challengePrompt(diff: string, stat: string): string {
  return `You are an adversarial reviewer. Your goal is to BREAK the code in this diff.
Find inputs, sequences, environments, or assumptions that make it fail.

Diff stat:
${stat}

Diff:
\`\`\`diff
${diff}
\`\`\`

For round 1, identify the 3-5 most likely failure modes. Be concrete: name the
exact input or sequence. Severity-tag each (BLOCKER / MAJOR / MINOR).

Format:
[SEVERITY] vector — concrete failure scenario. why it breaks. how to verify.`;
}

const challengeAngles = [
  "Now focus on concurrency and race conditions specifically. Where can two requests, two writers, or two state transitions interleave to produce a corrupt state?",
  "Now focus on error and partial-failure paths. What happens if the network call mid-way through this code times out? If the disk write fails? If a downstream service returns an unexpected shape?",
  "Now focus on security. Auth bypass, injection (SQL/command/prompt/path), unsafe deserialization, secrets leaking into logs, TOCTOU. Be specific about the input that triggers it.",
  "Now focus on the boundary conditions: empty input, null/undefined, max-size input, unicode edge cases, time/timezone, leap seconds, integer overflow. Pick the one most likely to actually hit prod.",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const base = detectBase(args.base);
  const { diff, stat, files } = getDiff(base);

  if (!diff) {
    console.error(`No diff against ${base}. Nothing to review.`);
    process.exit(0);
  }

  console.error(`[pi-skill] mode=${args.mode} base=${base} files=${files.length}${args.model ? ` model=${args.model}` : ""}`);

  const sessionOpts: any = { sessionManager: SessionManager.inMemory() };
  if (args.model) {
    // Format: "provider/modelId" e.g. "anthropic/claude-opus-4-5" or "foundry-codex/gpt-5.3-codex"
    const slash = args.model.indexOf("/");
    if (slash < 0) {
      console.error(`--model must be "provider/modelId" form. Got: ${args.model}`);
      console.error(`Run /pi models to see available combinations.`);
      process.exit(2);
    }
    const provider = args.model.slice(0, slash);
    const modelId = args.model.slice(slash + 1);
    try {
      sessionOpts.model = (getModel as any)(provider, modelId);
    } catch (err: any) {
      console.error(`getModel(${provider}, ${modelId}) failed: ${err?.message ?? err}`);
      process.exit(2);
    }
  }

  const { session } = await createAgentSession(sessionOpts);

  // Stream text deltas to stdout
  let captured = "";
  session.subscribe((event: any) => {
    if (event?.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
      const delta = event.assistantMessageEvent.delta ?? "";
      process.stdout.write(delta);
      captured += delta;
    }
  });

  if (args.mode === "review") {
    await session.prompt(reviewPrompt(diff, stat));
    process.stdout.write("\n");
    // Verdict line is in `captured`. Skill caller parses last PI_REVIEW_GATE line.
    return;
  }

  // Challenge mode
  await session.prompt(challengePrompt(diff, stat));
  process.stdout.write("\n");

  for (let round = 2; round <= args.rounds; round++) {
    const angle = challengeAngles[(round - 2) % challengeAngles.length];
    console.error(`\n[pi-skill] --- challenge round ${round}/${args.rounds} ---\n`);
    if (typeof (session as any).followUp === "function") {
      await (session as any).followUp(angle);
    } else if (typeof (session as any).steer === "function") {
      await (session as any).steer(angle);
    } else {
      // Fallback: prompt continues the same session
      await session.prompt(angle);
    }
    process.stdout.write("\n");
  }

  // Summary
  console.error(`\n[pi-skill] --- final summary ---\n`);
  await session.prompt(
    "Now produce a deduplicated, severity-sorted summary of all the breakages you found across rounds. " +
    "One line each: [SEVERITY] vector — scenario. fix priority. " +
    "End with: PI_CHALLENGE_GATE: {\"breakages\":N,\"blockers\":B,\"majors\":M}"
  );
  process.stdout.write("\n");
}

main().catch((err) => {
  console.error("[pi-skill] runner failed:", err?.message ?? err);
  process.exit(1);
});
