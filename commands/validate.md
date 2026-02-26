---
description: Validate implementation plan with Codex before coding
argument-hint: [path-to-plan] [--profile <name>]
allowed-tools: ["Read", "Write", "Bash", "Grep", "Glob", "TaskOutput"]
---

# Codex Plan Validation

Get an independent review of your implementation plan from Codex before writing code. Read the codex-validation skill for full reference.

## Determine Plan Source

Parse `$ARGUMENTS`:
- Path provided → read that file as the plan
- No args → look for active plan file at `.claude/plans/*.md` (most recent)
- `--profile <name>` → use a review profile to focus validation criteria

## Step 1: Prepare Context

Tell user: "Preparing Codex validation. Gathering plan and relevant code..."

Read all files referenced in the plan. Gather:
1. **Project context** — brief description, stack, key conventions from CLAUDE.md
2. **The plan** — full inline plan text with all steps
3. **Relevant code** — inline excerpts from key files
4. **Known risks** — any concerns already identified

## Step 2: Construct Prompt

Generate session:
```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

Build prompt following `references/prompt-patterns.md`. If `--profile` is active, use its focus areas and criteria. Include confidence rating instructions.

For large plans (5+ steps or 3+ files), use **parallel split**:
- Prompt 1: correctness, bugs, edge cases, type safety
- Prompt 2: architecture, patterns, naming, conventions

Tell user: "Sending to Codex. Prompt is ~[N] words..."

## Step 3: Run Codex

**All Codex calls use `run_in_background: true` with timeout 300000.**

```bash
cat .claude/codex/$SESSION_ID/prompt.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-plan.jsonl
```

Use absolute path for `--output-schema`: `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`

Tell user: "Codex validation started..."

**Monitor Codex progress** while it runs — use `TaskOutput(task_id=<id>, block=false, timeout=30000)` every ~30s. Report progress: event count, last activity type, elapsed time. See SKILL.md "Progress Monitoring" for format.

## Step 4: Evaluate

Extract results:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-plan.jsonl --output
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-plan.jsonl --progress
```

Evaluate each finding using confidence-aware triage:
- HIGH severity + HIGH confidence → auto-accept
- HIGH severity + LOW confidence → investigate first
- LOW severity + any → present but don't block

Tell user accept/reject decisions with reasoning.

## Step 5: Iterate (if needed)

If REQUEST_CHANGES or APPROVE_WITH_CHANGES:
1. Accept valid findings — update the plan
2. Reject invalid findings — document reasoning
3. Write evaluation to `.claude/codex/$SESSION_ID/claude-evaluation.md`
4. Resume or cross-review if disagreements remain

**Circuit breaker**: max 3 iterations, stop on stagnation or token budget.

## Step 6: Present Results

Present the validated plan with:
- Updated plan (if changes accepted)
- Summary of findings and how addressed
- Remaining disagreements for user decision
- Total iterations, token usage, final verdict
