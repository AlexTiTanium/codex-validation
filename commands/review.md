---
description: Pair code review — Claude and Codex independently review then cross-validate each other's decisions
argument-hint: [uncommitted|branch <base>|commit <sha>] [--profile <name>] [--persona <name>] [--fix]
allowed-tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "TaskOutput"]
---

# Codex Pair Review

Claude and Codex independently review code, then validate each other's findings. This pair approach catches more real issues than either reviewer alone.

Read the codex-validation skill for full reference.

## Determine Scope

Parse `$ARGUMENTS`:
- No args or `uncommitted` → review uncommitted changes
- `branch <base>` → review changes against base branch
- `commit <sha>` → review specific commit

**Optional flags:**
- `--profile <name>` → review profile (security-audit, performance, quick-scan, pre-commit, api-review)
- `--persona <name>` → reviewer persona (senior-engineer, security-researcher, performance-engineer, junior-mentor, devil-advocate)
- `--fix` → auto-fix accepted MECHANICAL findings after review

## Step 1: Assess & Configure

Run `git diff --stat` (or `git diff --stat <base>...HEAD` for branch) to determine scope.

**Load configuration layers (precedence: policy > profile > persona > defaults):**
1. **Policy**: Read `.codex-policy.json` from project root (if exists)
2. **Profile**: If `--profile`, read from `references/profiles/<name>.md`
3. **Persona**: If `--persona`, read from `references/personas/<name>.md` or `.codex-personas.md`

Tell user: "Pair review of [N] files. Config: [profile/persona/policy if active]"

## Step 2: Independent Reviews (Parallel)

Both reviewers analyze independently without seeing each other's work.

Generate session:
```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

**Claude's review:** Analyze the code yourself. Write findings to `.claude/codex/$SESSION_ID/claude-review.md` with severity, confidence, category, file, line, description, suggestion.

**Codex's review (background):** Build prompt following `references/prompt-patterns.md`. Inject profile focus areas and persona role if active. Inline all code and CLAUDE.md conventions.

```bash
cat .claude/codex/$SESSION_ID/prompt-review.md | codex exec --json --sandbox read-only --ephemeral --output-schema /absolute/path/to/review-output-schema.json - | tee .claude/codex/$SESSION_ID/events-review.jsonl
```

Use `run_in_background: true`, timeout 300000. Use absolute path for `--output-schema`: `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`

Tell user: "Both reviewers analyzing independently..."

**Monitor Codex progress** while it runs — use `TaskOutput(task_id=<id>, block=false, timeout=30000)` every ~30s. Report progress: event count, last activity type, elapsed time. See SKILL.md "Progress Monitoring" for format.

When Codex completes, extract:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION_ID/events-review.jsonl --output > .claude/codex/$SESSION_ID/codex-review.json
```

Report: "Independent review done. Claude found [N] issues, Codex found [M] issues."

## Step 3: Cross-Validation (Parallel)

Each reviewer validates the other's findings.

**Claude validates Codex:** Read Codex's findings. For each: ACCEPT (with evidence), REJECT (with reasoning), or PARTIAL. Save to `.claude/codex/$SESSION_ID/claude-validates-codex.md`.

**Codex validates Claude (background):** Inline Claude's findings in a prompt. Ask Codex to evaluate each finding with AGREE/DISAGREE/PARTIALLY_AGREE and provide evidence. Run with `--json --ephemeral`.

```bash
cat .claude/codex/$SESSION_ID/prompt-cross-validate.md | codex exec --json --sandbox read-only --ephemeral - | tee .claude/codex/$SESSION_ID/events-cross-validate.jsonl
```

Tell user: "Cross-validating each other's findings..."

**Monitor Codex progress** — poll with `TaskOutput(block=false)` every ~30s. Report updates.

## Step 4: Synthesize

Read both cross-validation results. Produce final findings:

**Deduplicate:**
- Exact-match (same file + line + category) → merge, keep highest severity/confidence
- Near-match (same file, lines within 5, similar category) → flag as "may be related"

**Classify by agreement:**
- **Both found it** → CONFIRMED (highest confidence)
- **One found, other validated** → ACCEPTED
- **One found, other rejected** → present both positions for user decision

**Apply policy** (if `.codex-policy.json` exists):
- Non-overridable findings → always blocking
- Auto-dismiss rules → apply only to unconfirmed findings
- Log suppressions in `meta.json`

**Classify fixability** per `references/severity-taxonomy.md`:
- MECHANICAL (auto-fixable), GUIDANCE (needs human), ARCHITECTURAL (needs redesign)

Write synthesis to `.claude/codex/$SESSION_ID/synthesis.md` and `meta.json`.

## Step 5: Auto-Fix (if `--fix`)

If `--fix` was specified and there are accepted MECHANICAL findings:

1. Create safety branch: `git checkout -b codex-fix-$SESSION_ID`
2. Apply each MECHANICAL fix using Edit tool, show diff for each
3. Verify with Codex (`codex exec --json --sandbox read-only --ephemeral`)
4. If verification passes → done. If fails → rollback via `git checkout`
5. `--dry-run` variant: use `--fix --dry-run` to preview fixes without applying

Max 3 fix-verify rounds (circuit breaker). Present GUIDANCE and ARCHITECTURAL findings as recommendations only.

## Step 6: Present Results

```
=== Pair Review Results ===
Scope: [N] files, [mode]
CONFIRMED (both found):  [N] findings
ACCEPTED (cross-validated): [M] findings
DISPUTED (disagreement): [K] findings — needs your decision

Findings by severity: [N] CRITICAL, [M] HIGH, [K] MEDIUM, [J] LOW
Fixability: [N] MECHANICAL, [M] GUIDANCE, [K] ARCHITECTURAL
Verdict: APPROVE | APPROVE_WITH_CHANGES | REQUEST_CHANGES
Tokens: [X]K input / [Y]K output
```

List all findings grouped by confidence level. For disputed findings, show both positions.
