---
description: Quick Codex review of uncommitted changes or branch diff
argument-hint: [uncommitted|branch <base>|commit <sha>]
allowed-tools: ["Read", "Write", "Bash", "Grep", "Glob"]
---

# Codex Code Review

Run an independent code review using OpenAI Codex CLI. Read the codex-validation skill for full reference.

## Determine Scope

Parse `$ARGUMENTS` to determine review mode:
- No args or `uncommitted` → review uncommitted changes
- `branch <base>` → review changes against base branch
- `commit <sha>` → review specific commit

## Step 1: Assess Changes

Run `git diff --stat` (or `git diff --stat <base>...HEAD` for branch) to determine the scope.

Tell the user: "Preparing Codex code review of [N] changed files..."

## Step 2: Prepare Review

Read the changed files yourself. If the scope touches 3+ files, use **parallel split** (two focused reviews: correctness vs architecture).

Generate a session ID:
```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

For parallel split, write two prompt files following `references/prompt-patterns.md` templates — one focused on correctness, one on architecture. Inline all relevant code and CLAUDE.md conventions.

For single review (< 3 files), write one prompt file.

## Step 3: Run Codex

Tell the user: "Running Codex review now. Prompt is ~[N] words..."

**All Codex calls use `run_in_background: true` with timeout 300000.**

For parallel split (two calls in one message):
```bash
cat .claude/codex/$SESSION_ID/prompt-correctness.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-correctness.jsonl
```
```bash
cat .claude/codex/$SESSION_ID/prompt-architecture.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-architecture.jsonl
```

Use absolute path for `--output-schema`: `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`

Immediately tell the user: "Codex review started. Analyzing [N] files..."

## Step 4: Read and Evaluate

When notified of completion, extract results:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-correctness.jsonl --output
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-correctness.jsonl --progress
```

Report to user immediately: total findings, severity breakdown, verdict.

Evaluate each finding using the **confidence-aware triage** matrix from the skill:
- Check accuracy, relevance, specificity, actionability
- HIGH severity + HIGH confidence → auto-accept
- HIGH severity + LOW confidence → investigate first

Tell user: "Accepting [N] findings, rejecting [M]. Here's the breakdown: [details]"

## Step 5: Iterate (if needed)

If Codex returned REQUEST_CHANGES and valid findings were accepted:

1. Make code corrections for accepted findings
2. Write formal evaluation to `.claude/codex/$SESSION_ID/claude-evaluation.md`
3. Resume or re-run with cross-review protocol (see skill)
4. **Circuit breaker**: max 3 iterations, stop on stagnation or token budget

Track iteration state in `.claude/codex/$SESSION_ID/meta.json`.

## Step 6: Present Results

Present final summary:
- Findings accepted and changes made
- Findings rejected with reasoning
- Any remaining disagreements for user decision
- Token usage and iteration count
