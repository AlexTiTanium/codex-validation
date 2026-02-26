---
name: codex-validation
description: >-
  This skill should be used when the user asks to "validate with codex",
  "get codex review", "codex validation", "cross-validate with codex",
  "second opinion from codex", "run codex review", "have codex check this",
  "codex code review", "ask codex to review my diff", "codex review the plan",
  "independent review with codex", or mentions wanting OpenAI Codex CLI
  feedback on a plan, code changes, uncommitted diff, or branch comparison.
  Also triggered during feature-dev workflows when the user says "validate
  the plan with codex" or "get codex feedback on the architecture".
---

# Codex Validation — Core Knowledge Base

Use OpenAI Codex CLI (`codex exec`) as an independent review agent to cross-validate implementation plans and code changes. Commands: `/codex:review`, `/codex:validate`, `/codex:debate`.

## Prerequisites

- Codex CLI installed and available as `codex` on PATH (typically `/opt/homebrew/bin/codex` on macOS ARM via Homebrew cask)
- Authenticated via ChatGPT account or API key
- Config at `~/.codex/config.toml`
- `jq` installed (for JSONL parsing)

## Exchange Directory

All prompt and output files use `.claude/codex/<session-id>/` in the project root instead of `/tmp/`. This avoids Claude Code permission prompts since the project directory is always allowed.

- **Session isolation:** Each invocation gets a unique subdirectory (`<timestamp>-<pid>`)
- Auto-created: `mkdir -p .claude/codex/<session-id>`
- Already gitignored (`.claude` is in `.gitignore`)
- Readable by Codex in `--sandbox read-only`

```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

**Never use `/tmp/` for exchange files.**

## Inline Content Rule (CRITICAL)

**ALWAYS inline the full plan/code content directly in the Codex prompt.** Never tell Codex to "read file X" — Codex has issues reliably reading files.

For prompts over ~6000 words, write to `.claude/codex/prompt-context.md` and tell Codex to read from there.

## JSONL Streaming

All Codex invocations use `--json` flag for JSONL event streaming.

**Event types:** `thread.started`, `turn.started`, `item.started`, `item.completed`, `turn.completed`, `turn.failed`, `error`

**Item types:** `agent_message`, `reasoning`, `command_execution`, `file_changes`, `mcp_tool_call`, `web_search`

JSONL events are written to stdout in real-time and are **accessible mid-flight** via `TaskOutput(block=false)` on the background task. This enables live progress monitoring (see Progress Monitoring section).

```bash
# Get structured findings (after completion)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --output

# Get progress summary (after completion)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --progress

# Check for errors (after completion)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --errors
```

## Background Execution (MANDATORY)

ALL Codex Bash commands MUST use `run_in_background: true`. Set timeout to 300000ms (5 minutes).

1. Write the prompt file (foreground)
2. Start Codex with `run_in_background: true` — note the **task ID** returned
3. Send initial progress message
4. **Monitor with `TaskOutput`** — poll every ~30s (see Progress Monitoring below)
5. When completed, extract results

**For parallel runs:** Launch multiple background Bash calls in a single message. Monitor each task ID independently.

**Shell variable gotcha:** Do NOT use `VAR=x && codex ...` in background mode. Use absolute paths directly.

## Progress Monitoring

While Codex runs in the background, use `TaskOutput` to show the user what's happening. Default interval is **30 seconds** (adjustable per command).

### How It Works

Codex writes JSONL events to stdout in real-time. `TaskOutput(block=false)` returns accumulated stdout from the background process — including JSONL events written so far. This gives live visibility into Codex's progress.

### Polling Loop

After launching a background Codex task:

```
1. Call TaskOutput(task_id=<id>, block=false, timeout=30000)
2. If status is "running":
   a. Count JSONL events in output (grep for "item.completed")
   b. Find last activity type (reasoning, web_search, command_execution, agent_message)
   c. Report to user: "Codex working... [N] events, last: [type], [Xs] elapsed"
   d. Wait ~30s, repeat from step 1
3. If status is "completed":
   a. Extract results as normal
```

### Progress Message Format

Report concise updates — do NOT dump raw JSONL. Example messages:

- `"Codex working... 5 events, 23s elapsed, last: reasoning"`
- `"Codex working... 12 events, 48s elapsed, last: web_search (researching docs)"`
- `"Codex working... 28 events, 1m 15s elapsed, last: command_execution"`
- `"Codex done. 34 events, 1m 42s. Extracting results..."`

### Extracting Progress from JSONL

To count events and find the last activity from TaskOutput's raw output, scan for `item.completed` entries. Key event types to surface:

| JSONL item type | User-facing label |
|-----------------|-------------------|
| `reasoning` | thinking |
| `web_search` | researching |
| `command_execution` | running commands |
| `agent_message` | composing response |
| `file_changes` | editing files |

### Configuration

- **Default interval:** 30 seconds
- **Adjustable:** Commands can specify a different interval (e.g., `--poll-interval 15`)
- **No cap on polls:** Continue until task completes. Token cost per poll is minimal (~1-2K tokens).
- **Parallel tasks:** When monitoring 2+ tasks, check each in sequence within a single polling round

## Structured Output

Use `--output-schema` for structured JSON. Schema at `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`.

```json
{
  "findings": [
    {
      "severity": "HIGH",
      "confidence": "HIGH",
      "category": "correctness",
      "file": "src/example.ts",
      "line": 42,
      "description": "Missing null check on result",
      "suggestion": "Add early return if result is null"
    }
  ],
  "verdict": "REQUEST_CHANGES",
  "summary": "One critical gap in error handling."
}
```

**Availability:** `--output-schema` only works on `codex exec`, NOT on `codex exec review` or `codex exec resume`.

## Severity & Fixability

Definitions in `references/severity-taxonomy.md`:

- **Severity:** CRITICAL > HIGH > MEDIUM > LOW
- **Confidence:** HIGH (verified) > MEDIUM (sound reasoning) > LOW (speculative)
- **Fixability:** MECHANICAL (auto-fixable), GUIDANCE (needs human), ARCHITECTURAL (needs redesign)
- **Precedence:** policy > profile > persona > defaults

## Policy Engine

Optional `.codex-policy.json` at project root. Schema: `references/policy-schema.json`.

```json
{
  "blocking": ["security", "correctness"],
  "warning": ["convention", "alternative"],
  "auto_dismiss": { "max_severity": "LOW", "max_confidence": "LOW" },
  "non_overridable": ["CRITICAL+security", "CRITICAL+correctness"]
}
```

**Evaluation:** non-overridable check → auto-dismiss → blocking/warning classification → log suppressions to `meta.json`.

**Safety:** `auto_dismiss.max_severity` cannot be HIGH/CRITICAL. CRITICAL security/correctness can never be dismissed.

## Confidence-Aware Triage

Default triage when no policy file exists:

| Severity | Confidence | Action |
|----------|------------|--------|
| HIGH/CRITICAL | HIGH | Auto-accept |
| HIGH/CRITICAL | LOW | Investigate first |
| MEDIUM | HIGH | Accept |
| MEDIUM | MEDIUM | Accept with scrutiny |
| LOW | any | Present but don't block |
| any | Both agents agree | Definite accept |

**Dismiss:** Generic advice, codebase misunderstandings, style preferences contradicting CLAUDE.md, findings covered by tests/linting.

## Circuit Breaker

Stop when ANY triggers:
1. **Stagnation**: 2+ iterations with 0 accepted → STOP
2. **Recycling**: Same finding in 2+ iterations → ESCALATE to user
3. **Token budget**: 100K input tokens → STOP
4. **Timeout**: 5 minutes per Codex call → KILL

Track in `.claude/codex/<session>/meta.json`.

## Pair Review Protocol

Used by `/codex:review`. Both Claude and Codex review independently, then cross-validate each other's decisions.

1. **Independent review** — both analyze without seeing each other's work
2. **Cross-validation** — each evaluates the other's findings (ACCEPT/REJECT/PARTIAL)
3. **Synthesis** — merge results by agreement level:
   - CONFIRMED (both found it) → highest confidence
   - ACCEPTED (one found, other validated) → high confidence
   - DISPUTED (disagreement) → present both positions for user

## Debate Protocol (4-Phase)

Used by `/codex:debate`. Both sides can use internet research to back positions.

**Phase 1 — Independent Review (parallel)**
- Claude → `phase1-claude.md`
- Codex → `phase1-codex.json`

**Phase 2 — Cross-Review with Evidence (parallel)**
- Each critiques the other's findings
- Use WebSearch/WebFetch (Claude) and web_search (Codex) to find docs, RFCs, benchmarks
- AGREE / DISAGREE / PARTIALLY_AGREE with cited sources

**Phase 3 — Defense Round (parallel)**
- Each responds to critique: defend with evidence or concede
- Final chance to cite internet sources

**Phase 4 — Synthesis (Claude only)**
- Agreed → definitive. Defended → note winning side + evidence. Unresolved → user decides.

**Cost:** 3 Codex calls. Circuit breaker applies per-phase.

## Quick Mode (`--quick`)

Available on all commands. Reduces phases, reasoning effort, and severity scope for faster turnaround.

### Argument Parsing

- `--quick` → reasoning effort = `low`, severity = CRITICAL+HIGH only, phases reduced
- `--quick medium` → reasoning effort = `medium`, phases reduced
- `--quick high` → reasoning effort = `high`, phases reduced
- Valid effort values: `low`, `medium`, `high` (not `xhigh`)
- If the token after `--quick` is not a valid effort level, treat it as the next argument and default to `low`

### Phase Reduction

| Command | Default Phases | Quick Phases | Skipped |
|---------|---------------|-------------|---------|
| `/codex:review` | Independent review + Cross-validation + Synthesis | Independent review + Synthesis | Cross-validation |
| `/codex:validate` | Codex review + up to 3 iterations | Codex review only (single prompt) | Parallel split + iterations |
| `/codex:debate` | Independent review + Cross-review + Defense + Synthesis | Independent review + Synthesis | Cross-review, Defense |

### Severity Filter

When quick mode is active and NO `--profile` is explicitly specified:
- Only include findings with severity CRITICAL or HIGH
- Drop MEDIUM and LOW before presenting results
- Recompute verdict after filtering: if no findings remain, verdict is APPROVE

When quick mode is active WITH an explicit `--profile`:
- Use the profile's own severity filter
- Quick mode still reduces phases and overrides reasoning effort

### Reasoning Effort Precedence

```
--quick [effort]   (highest priority)
  ↓
Profile reasoning  (from references/profiles/<name>.md)
  ↓
Default: "medium"
```

### Composability

- `--quick --fix` → quick review + auto-fix accepted MECHANICAL findings
- `--quick --profile security-audit` → quick phases + security criteria + profile's severity filter
- `--quick --persona devil-advocate` → quick phases + adversarial persona
- `--quick medium --profile performance --persona performance-engineer` → all combine

### Synthesis Adjustments

- **Review (no cross-validation):** Dedup Claude + Codex findings. Both-found = CONFIRMED. Single = INDEPENDENT.
- **Validate (no iteration):** Accept Codex findings after Claude's evaluation. No follow-up.
- **Debate (no cross-review/defense):** Compare Claude + Codex independent findings. Both-found = AGREED. Single = UNIQUE.

## Review Profiles

Profiles tune *what* to look at. In `references/profiles/`.

**Available:** `security-audit`, `performance`, `quick-scan`, `pre-commit`, `api-review`

Each contains: Focus Areas, Review Criteria, Reasoning Effort, Severity Filter, Prompt Injection.

**Usage:** `--profile security-audit` on review or validate.

## Custom Personas

Personas tune *how* to look at it. In `references/personas/`.

**Available:** `senior-engineer`, `security-researcher`, `performance-engineer`, `junior-mentor`, `devil-advocate`

Replaces the default role line. Custom personas via `.codex-personas.md` at project root.

**Usage:** `--persona devil-advocate` on review or debate.

**Profiles + personas compose:** `--profile security-audit --persona devil-advocate` = security-focused adversarial review.

## Deduplication

When multiple streams produce findings (pair review, debate phases), deduplicate before presenting.

**Tier 1 — Automatic:** Same file + line + category → merge, keep highest severity/confidence.
**Tier 2 — Suggested:** Same file + lines within 5 + similar category → "may be related" for user decision.

Cross-cutting findings (file: "general"): only merge if category AND description are nearly identical.

## Auto-Fix (--fix flag)

On `/codex:review --fix`, auto-fix accepted MECHANICAL findings:

1. Create safety branch (`codex-fix-<session>`)
2. Apply fixes via Edit tool, show diff
3. Verify with Codex
4. Rollback on failed verification

Only MECHANICAL findings. Max 3 rounds. `--fix --dry-run` to preview without applying.

## Parallel Execution

Split into 2 parallel Codex calls for broad scope:

**When:** 3+ files or 5+ plan steps.
**Split:** Logic & Correctness vs Architecture & Conventions.

## Handling Failures

- **Timeout**: Present partial findings, suggest smaller scope
- **Auth error**: Run `codex` interactively to re-authenticate
- **Unhelpful feedback**: More specific prompt
- **Convention disagreement**: Override citing CLAUDE.md
- **JSONL parse error**: Fall back to raw events file

## Reference Files

- **`references/codex-cli-reference.md`** — CLI flags and configuration
- **`references/prompt-patterns.md`** — Prompt templates for all commands
- **`references/review-output-schema.json`** — JSON Schema for structured output
- **`references/severity-taxonomy.md`** — Severity, confidence, fixability definitions
- **`references/policy-schema.json`** — Schema for `.codex-policy.json`
- **`references/profiles/`** — Review profile definitions (5 built-in)
- **`references/personas/`** — Reviewer persona definitions (5 built-in)

## Scripts

- **`scripts/codex-validate.sh`** — Plan validation, session resume, review, exec wrapper
- **`scripts/codex-review-diff.sh`** — Git diff review wrapper
- **`scripts/parse-jsonl.sh`** — Extract output, progress, or errors from JSONL
