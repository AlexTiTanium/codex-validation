---
description: Adversarial debate — Claude and Codex argue back and forth, using internet research to prove positions
argument-hint: [uncommitted|plan <path>|branch <base>] [--persona <name>]
allowed-tools: ["Read", "Write", "Bash", "Grep", "Glob", "Task", "TaskOutput", "WebSearch", "WebFetch"]
---

# Codex Adversarial Debate

Claude and Codex debate code or plans through multiple rounds. Each side can use internet research (docs, RFCs, benchmarks) to back their positions. Read the codex-validation skill for full reference.

## Determine Scope

Parse `$ARGUMENTS`:
- `uncommitted` or no args → review uncommitted code changes
- `plan <path>` → review an implementation plan
- `branch <base>` → review branch diff against base
- `--persona <name>` → persona for Codex's prompts

## Setup

```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

Read the target content. Load policy (`.codex-policy.json` if exists) and persona if specified.

Tell user: "Starting adversarial debate. 4 phases, 3 Codex calls. Expected: 3-5 minutes."

## Phase 1 — Independent Review (Parallel)

Both review independently without seeing each other's work.

**Claude's review:** Analyze the code/plan. Write findings to `.claude/codex/$SESSION_ID/phase1-claude.md` with severity, confidence, file, line, description, suggestion.

**Codex's review (background):**
```bash
cat .claude/codex/$SESSION_ID/prompt-phase1.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-phase1.jsonl
```
Use `run_in_background: true`, timeout 300000. Absolute path for schema: `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`

Tell user: "Phase 1: Both reviewers analyzing independently..."

**Monitor Codex progress** while it runs — use `TaskOutput(task_id=<id>, block=false, timeout=30000)` every ~30s. Report progress: event count, last activity type, elapsed time. See SKILL.md "Progress Monitoring" for format.

Extract findings when done:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-phase1.jsonl --output > .claude/codex/$SESSION_ID/phase1-codex.json
```

Report: "Phase 1 done. Claude: [N] issues, Codex: [M] issues."

## Phase 2 — Cross-Review with Evidence (Parallel)

Each reviewer critiques the other's findings. **Use internet research to prove or disprove claims.**

**Claude critiques Codex:** Read Codex's findings. For each:
- **AGREE** — with reasoning and evidence
- **DISAGREE** — with counter-evidence. Use WebSearch/WebFetch to find docs, RFCs, or benchmarks that support your position
- **PARTIALLY_AGREE** — explain what's right and wrong

Save to `.claude/codex/$SESSION_ID/phase2-claude-on-codex.md`. Include URLs for any internet sources cited.

**Codex critiques Claude (background):** Inline Claude's findings. Tell Codex to use web search to verify claims where possible. The prompt should instruct: "Search the internet for documentation, RFCs, or benchmarks to support your position when disagreeing."

```bash
cat .claude/codex/$SESSION_ID/prompt-phase2.md | codex exec --json --sandbox read-only --ephemeral - | tee .claude/codex/$SESSION_ID/events-phase2.jsonl
```

Tell user: "Phase 2: Cross-reviewing with evidence..."

**Monitor Codex progress** — poll with `TaskOutput(block=false)` every ~30s. Report updates.

## Phase 3 — Defense Round (Parallel)

Each reviewer responds to the other's critique. Final chance to defend or concede.

**Claude's defense:** For each disagreement from Codex:
- Defend with stronger evidence (use internet research if needed)
- Or concede if Codex's argument is sound

Save to `.claude/codex/$SESSION_ID/phase3-claude-meta.md`.

**Codex's defense (background):** Inline Claude's critique. Ask Codex to defend or concede, citing sources.

```bash
cat .claude/codex/$SESSION_ID/prompt-phase3.md | codex exec --json --sandbox read-only --ephemeral - | tee .claude/codex/$SESSION_ID/events-phase3.jsonl
```

Tell user: "Phase 3: Final defense round..."

**Monitor Codex progress** — poll with `TaskOutput(block=false)` every ~30s. Report updates.

## Phase 4 — Synthesis (Claude Only)

Read ALL 6 artifacts from phases 1-3.

**Deduplicate:** Same as review command — exact-match merge, near-match flag.

**Classify by debate outcome:**
- **Agreed** (both converge) → HIGH confidence, definitive
- **Defended** (one side won with evidence) → MEDIUM confidence, note which side and why
- **Unresolved** → present both positions with sources for user decision

**Apply policy** if `.codex-policy.json` exists. **Classify fixability** per severity-taxonomy.md.

Write synthesis to `.claude/codex/$SESSION_ID/synthesis.md` and `meta.json`.

## Circuit Breaker

- Token budget: 100K input tokens across all Codex calls
- Per-phase timeout: 5 minutes
- If any phase fails, present findings from completed phases

## Present Results

```
=== Debate Results ===
Agreed findings:    [N] (both converged)
Defended findings:  [M] (one side won with evidence)
Unresolved:         [K] (needs your decision)

Sources cited: [N] URLs referenced during debate
Verdict: APPROVE | APPROVE_WITH_CHANGES | REQUEST_CHANGES
Tokens: [X]K input / [Y]K output (3 Codex calls)
```

For defended findings, explain which side won and what evidence decided it. For unresolved, show both positions with cited sources.
