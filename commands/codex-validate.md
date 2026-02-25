---
description: Validate implementation plan with Codex before coding
argument-hint: [path-to-plan]
allowed-tools: ["Read", "Write", "Bash", "Grep", "Glob"]
---

# Codex Plan Validation

Run an independent plan review using OpenAI Codex CLI. Read the codex-validation skill for full reference.

## Determine Plan Source

Parse `$ARGUMENTS`:
- Path provided → read that file as the plan
- No args → look for active plan file at `.claude/plans/*.md` (most recent)

## Step 1: Prepare Context

Tell the user: "Preparing Codex validation context. Gathering plan details and relevant code..."

Read all files referenced in the plan yourself. Gather:
1. **Project context** — brief description, stack, key conventions from CLAUDE.md
2. **Feature requirements** — what the feature should accomplish
3. **The plan** — full inline plan text with all implementation steps
4. **Relevant code** — inline excerpts from key files
5. **Known risks** — any concerns already identified

## Step 2: Construct Prompt

Tell the user: "Constructing review prompt with [N] files inlined, covering [brief scope]..."

Build prompt following `references/prompt-patterns.md` templates. Include confidence rating instructions.

For plans with 5+ steps or touching 3+ files, use **parallel split**:
- Prompt 1: correctness, bugs, edge cases, type safety
- Prompt 2: architecture, patterns, naming, project conventions

Generate a session ID and write prompt files:
```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

## Step 3: Run Codex

Tell the user: "Running Codex review now (round 1). Prompt is ~[N] words..."

**All Codex calls use `run_in_background: true` with timeout 300000.**

For parallel split (two calls in one message, both background):
```bash
cat .claude/codex/$SESSION_ID/prompt-correctness.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-correctness.jsonl
```
```bash
cat .claude/codex/$SESSION_ID/prompt-architecture.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-architecture.jsonl
```

Use absolute path for `--output-schema`: `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`

For single review (without `--ephemeral` for session resume):
```bash
cat .claude/codex/$SESSION_ID/prompt.md | codex exec --json --sandbox read-only --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-plan.jsonl
```

Immediately tell the user: "Codex validation started. Reviewing [scope]..."

## Step 4: Read and Evaluate

When notified of completion, extract results:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-plan.jsonl --output
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-plan.jsonl --progress
```

Report: total findings, severity+confidence breakdown, verdict.

Evaluate using confidence-aware triage matrix. Tell user your accept/reject decisions.

## Step 5: Iterate (Using Session Resume)

If REQUEST_CHANGES or APPROVE_WITH_CHANGES:

1. Accept valid findings — update the plan
2. Reject invalid findings — document reasoning
3. Write formal evaluation to `.claude/codex/$SESSION_ID/claude-evaluation.md`
4. Resume session or use cross-review protocol

**Circuit breaker active**: max 3 iterations, stop on stagnation/recycling/budget.
Track in `.claude/codex/$SESSION_ID/meta.json`.

## Step 6: Present Results

Present the validated plan with:
- Updated plan (if changes accepted)
- Summary of findings and how addressed
- Remaining disagreements for user decision
- Total iterations, token usage, final verdict
