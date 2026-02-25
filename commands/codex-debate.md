---
description: Full adversarial 4-phase review with Claude and Codex debating findings
argument-hint: [uncommitted|plan <path>|branch <base>]
allowed-tools: ["Read", "Write", "Bash", "Grep", "Glob", "Task"]
---

# Codex Adversarial Debate

Run a full 4-phase adversarial review where Claude and Codex independently review, cross-critique, defend positions, and synthesize findings. Read the codex-validation skill (Debate Protocol section) for full reference.

## Determine Scope

Parse `$ARGUMENTS`:
- `uncommitted` or no args → review uncommitted code changes
- `plan <path>` → review an implementation plan
- `branch <base>` → review branch diff against base

## Setup

Generate session ID and prepare the exchange directory:
```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

Read the target content (diff, plan, or code files). Prepare the context you'll need for all 4 phases.

Tell the user: "Starting adversarial debate review. This runs 4 phases with 3 Codex calls. Expected time: 3-5 minutes."

## Phase 1 — Independent Review (Parallel)

Both Claude and Codex review independently without seeing each other's work.

**Claude's review:**
Analyze the code/plan yourself. Write findings to `.claude/codex/$SESSION_ID/phase1-claude.md` with severity, confidence, file, line, description, suggestion for each issue.

**Codex's review (background):**
Write a focused prompt and run Codex:
```bash
cat .claude/codex/$SESSION_ID/prompt-phase1.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-phase1.jsonl
```
Use `run_in_background: true`, timeout 300000.

Tell user: "Phase 1: Both reviewers analyzing independently..."

When Codex completes, extract findings:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-phase1.jsonl --output > .claude/codex/$SESSION_ID/phase1-codex.json
```

Report: "Phase 1 complete. Claude found [N] issues, Codex found [M] issues."

## Phase 2 — Cross-Review (Parallel)

Each reviewer critiques the other's findings.

**Claude critiques Codex:**
Read Codex's phase 1 findings. For each, write AGREE (with reasoning), DISAGREE (with evidence), or PARTIALLY_AGREE. Save to `.claude/codex/$SESSION_ID/phase2-claude-on-codex.md`.

**Codex critiques Claude (background):**
Inline Claude's phase 1 findings in a prompt:
```
Another reviewer found these issues: [phase1-claude.md content]

For each finding:
- AGREE: if the issue is valid, explain why
- DISAGREE: if the issue is wrong, provide counter-evidence
- PARTIALLY_AGREE: if partially valid, explain what's right and wrong

Also identify any issues the other reviewer missed.
```
Run with `--json --ephemeral`. Save to `.claude/codex/$SESSION_ID/events-phase2.jsonl`.

Tell user: "Phase 2: Cross-reviewing each other's findings..."

## Phase 3 — Meta-Review (Parallel)

Each reviewer responds to the other's critique.

**Claude's meta-review:**
Read Codex's phase 2 critique. For each disagreement, either defend with stronger evidence or concede. Save to `.claude/codex/$SESSION_ID/phase3-claude-meta.md`.

**Codex's meta-review (background):**
Inline Claude's phase 2 critique in a prompt. Ask Codex to defend or concede each challenged finding. Run with `--json --ephemeral`. Save to `.claude/codex/$SESSION_ID/events-phase3.jsonl`.

Tell user: "Phase 3: Defending and conceding positions..."

## Phase 4 — Synthesis (Claude Only)

Read ALL 6 artifacts from phases 1-3:
1. `phase1-claude.md` — Claude's initial findings
2. `phase1-codex.json` — Codex's initial findings
3. `phase2-claude-on-codex.md` — Claude's critique of Codex
4. `phase2-codex-on-claude.json` — Codex's critique of Claude
5. `phase3-claude-meta.md` — Claude's defense/concessions
6. `phase3-codex-meta.json` — Codex's defense/concessions

Produce a final verdict:

**Agreed findings** (both reviewers converge) → HIGH confidence, present as definitive
**Defended findings** (one reviewer defended successfully) → MEDIUM confidence
**Unresolved disagreements** → Present both positions for user decision

Write synthesis to `.claude/codex/$SESSION_ID/synthesis.md`.

Write meta.json with cumulative token usage from all JSONL files.

## Circuit Breaker

Monitor across all phases:
- Total token budget: 100K input tokens across all Codex calls
- Per-phase timeout: 5 minutes
- If any phase fails, present findings from completed phases

## Present Results

Tell user the final summary:
- Count of agreed/defended/disputed findings
- Final verdict with confidence scores
- Total cost (tokens across 3 Codex calls)
- Any actions needed from the user (unresolved disputes)
