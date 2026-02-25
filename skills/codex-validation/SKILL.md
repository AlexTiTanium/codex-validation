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

Use OpenAI Codex CLI (`codex exec`) as an independent review agent to cross-validate implementation plans and code changes. Commands: `/codex:review`, `/codex:validate`, `/codex:debate`, `/codex:status`.

## Prerequisites

- Codex CLI installed and available as `codex` on PATH (typically `/opt/homebrew/bin/codex` on macOS ARM via Homebrew cask)
- Authenticated via ChatGPT account or API key
- Config at `~/.codex/config.toml`
- `jq` installed (for JSONL parsing)

## Exchange Directory

All prompt and output files use `.claude/codex/<session-id>/` in the project root instead of `/tmp/`. This avoids Claude Code permission prompts since the project directory is always allowed.

- **Session isolation:** Each invocation gets a unique subdirectory (`<timestamp>-<pid>`), so parallel runs never clobber each other
- Auto-created by the wrapper script: `mkdir -p .claude/codex/<session-id>`
- Already gitignored (`.claude` is in `.gitignore`)
- Readable by Codex in `--sandbox read-only` (sandbox allows all project files)

**Session ID handling:** When calling the wrapper script directly, each invocation auto-generates an ID. When writing prompt files manually (e.g., for parallel split), generate a session ID first:

```bash
SESSION_ID="$(date +%s)-$$"
mkdir -p .claude/codex/$SESSION_ID
```

**Never use `/tmp/` for exchange files.**

## Inline Content Rule (CRITICAL)

**ALWAYS inline the full plan/code content directly in the Codex prompt.** Never tell Codex to "read file X" or "see the plan at path Y" — Codex has issues reliably reading files and may miss critical context or hallucinate file contents.

### Fallback for Large Prompts (over 6000 words)

Write full content to `.claude/codex/prompt-context.md` and tell Codex to read from there — it's inside the project directory and accessible in read-only sandbox mode.

## JSONL Streaming

All Codex invocations use `--json` flag for JSONL event streaming. This replaces the previous `-o FILE` pattern and provides visibility into Codex's execution.

**Event types:** `thread.started`, `turn.started`, `item.started`, `item.completed`, `turn.completed`, `turn.failed`, `error`

**Item types:** `agent_message`, `reasoning`, `command_execution`, `file_changes`, `mcp_tool_call`, `web_search`

**Extracting results after Codex completes:**

```bash
# Get structured findings (plan validation / exec with --output-schema)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --output > .claude/codex/$SESSION/findings.json

# Get progress summary (tool calls, token usage)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --progress

# Check for errors
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --errors
```

**Compatibility:** `--json` and `--output-schema` coexist — the schema shapes the final `agent_message` content, while `--json` wraps all events as JSONL.

## Background Execution (MANDATORY)

ALL Codex Bash commands MUST use `run_in_background: true` on the Bash tool. This prevents the UI from freezing during Codex execution (30-120s) and lets you send progress messages while Codex works. Set timeout to 300000ms (5 minutes).

**Flow:**

1. Write the prompt file (foreground Bash call)
2. Start Codex with `run_in_background: true` — you will be notified when it completes
3. Immediately send a progress message: "Codex validation started. Reviewing [scope]..."
4. When notified of completion, extract results from JSONL and present

**For parallel runs:** Launch multiple background Bash calls in a single message. You'll be notified as each completes.

**Do NOT poll or sleep.** The Bash tool notifies you automatically.

**Shell variable gotcha with `run_in_background`:** Do NOT use `VAR=x && codex ...` patterns — the `&&` chain may not execute correctly in background mode. Instead, use absolute paths directly or set variables in a prior foreground Bash call.

## Structured Output

Plan validation and generic exec modes use `--output-schema` for structured JSON output. The schema is at `${CLAUDE_PLUGIN_ROOT}/skills/codex-validation/references/review-output-schema.json`.

**Output format (with confidence field):**

```json
{
  "findings": [
    {
      "severity": "HIGH",
      "confidence": "HIGH",
      "category": "correctness",
      "file": "src/game/janken/janken.sequence.ts",
      "line": 42,
      "description": "Missing null check on challenge result",
      "suggestion": "Add early return if resolveJankenChallenge returns null"
    }
  ],
  "verdict": "REQUEST_CHANGES",
  "summary": "Plan has one critical gap in error handling."
}
```

**Availability:** `--output-schema` only works on `codex exec`, NOT on `codex exec review` or `codex exec resume`.

## Confidence-Aware Evaluation

Each finding has both `severity` and `confidence`. Use this matrix for triage:

| Severity | Confidence | Action |
|----------|------------|--------|
| HIGH/CRITICAL | HIGH | Auto-accept — concrete evidence exists |
| HIGH/CRITICAL | LOW | Investigate first — verify before accepting |
| MEDIUM | HIGH | Accept — sound reasoning verified |
| MEDIUM | MEDIUM | Accept with minor scrutiny |
| LOW | any | Present but don't block |
| any | HIGH (both agents agree in debate) | Definite accept |

**Dismiss findings that are:**
- Generic best-practice advice not specific to the change
- Based on misunderstanding the codebase architecture
- Style preferences contradicting project conventions (CLAUDE.md)
- Already covered by existing tests or linting

## Circuit Breaker

Stop iteration when ANY of these trigger:

1. **Stagnation**: 2+ consecutive iterations with 0 accepted findings → STOP
   - Report: "Review stalled — Codex keeps finding issues Claude rejects. Presenting disagreements."
2. **Issue recycling**: Same finding (same file + same description) appears in 2+ iterations → ESCALATE
   - Report: "Recurring disagreement on [finding]. Presenting both positions for your decision."
3. **Token budget**: Cumulative tokens across all iterations exceed 100K input tokens → STOP
   - Report: "Token budget reached ([N]K tokens). Presenting current findings."
4. **Timeout**: Any single Codex call exceeds 5 minutes → KILL + REPORT
   - Report: "Codex timed out after 5 minutes. Presenting partial findings from earlier rounds."

**Track state** in `.claude/codex/<session>/meta.json`:

```json
{
  "iterations": 2,
  "total_input_tokens": 48000,
  "total_output_tokens": 3200,
  "findings_history": [
    {"iter": 1, "found": 4, "accepted": 2, "rejected": 2},
    {"iter": 2, "found": 1, "accepted": 1, "rejected": 0}
  ],
  "circuit_breaker": null,
  "elapsed_seconds": 95
}
```

Extract token usage from JSONL events after each Codex call:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/$SESSION/events.jsonl --progress
```

## Cross-Review Protocol

After Codex produces findings and Claude evaluates them:

1. **Claude writes formal evaluation** to `.claude/codex/<session>/claude-evaluation.md`:
   - For each finding: ACCEPT with reasoning, or REJECT with evidence
   - Overall assessment: what Claude agrees with, what it disputes

2. **Feed evaluation back to Codex** (via exec with inlined content):
   ```
   Here is another reviewer's evaluation of your findings:
   [claude-evaluation.md content]

   For rejected findings: provide counter-evidence or concede.
   For accepted findings: confirm the fix approach is correct.
   Re-assess your verdict considering the other reviewer's perspective.
   ```

3. **Codex responds** with revised findings (some defended, some conceded)

4. **Claude synthesizes**: merge agreed findings, present persistent disagreements to user

## Debate Protocol (4-Phase)

Full adversarial review with structured argumentation. Triggered by `/codex:debate`.

**Phase 1 — Independent Review (parallel)**
- Claude reviews independently → `.claude/codex/<session>/phase1-claude.md`
- Codex reviews independently → `.claude/codex/<session>/phase1-codex.json` (via `--json | tee`)
- Both use confidence ratings

**Phase 2 — Cross-Review (parallel)**
- Claude critiques Codex's findings → `.claude/codex/<session>/phase2-claude-on-codex.md`
- Codex critiques Claude's findings → `.claude/codex/<session>/phase2-codex-on-claude.json`

**Phase 3 — Meta-Review (parallel)**
- Claude responds to Codex's critique → `.claude/codex/<session>/phase3-claude-meta.md`
- Codex responds to Claude's critique → `.claude/codex/<session>/phase3-codex-meta.json`

**Phase 4 — Synthesis (Claude only)**
- Read ALL 6 artifacts from phases 1-3
- Produce final verdict with confidence-weighted findings
- Present disagreements with both positions for user decision

**Cost:** 3 Codex calls (phases 1-3). Circuit breaker applies per-phase.

## Parallel Execution Strategy

For any validation with broad scope, split into 2 parallel Codex calls. This uses more tokens but cuts wall-clock time in half.

**When to use parallel:** Plans with 5+ steps, reviews touching 3+ files, or scope spanning multiple modules.
**When to use single:** Focused changes to 1-2 files or plans with < 5 steps.

**Split dimensions (always these two):**
1. **Logic & Correctness** — bugs, edge cases, error handling, type safety
2. **Architecture & Conventions** — patterns, naming, module boundaries, project conventions

## Handling Failures

- **Codex timeout**: Kill process, present partial findings, suggest smaller scope
- **Authentication error**: Run `codex` interactively once to re-authenticate
- **Unhelpful feedback**: Try a more specific prompt with concrete file references
- **Codex disagrees with project conventions**: Override with documented reasoning citing CLAUDE.md
- **JSONL parse error**: Fall back to reading raw events file, report parsing issue

## Reference Files

- **`references/codex-cli-reference.md`** - Complete CLI flags, flag availability matrix, and configuration details
- **`references/prompt-patterns.md`** - Prompt templates for plan validation, code review, cross-review, debate, and iteration
- **`references/review-output-schema.json`** - JSON Schema for structured output (with confidence field)

## Scripts

- **`scripts/codex-validate.sh`** - Wrapper for plan validation, session resume, review, and generic exec (JSONL output)
- **`scripts/codex-review-diff.sh`** - Wrapper for git-based code review (JSONL output)
- **`scripts/parse-jsonl.sh`** - Extract structured output, progress summary, or errors from JSONL events
