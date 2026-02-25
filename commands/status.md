---
description: Show last Codex validation session results and costs
allowed-tools: ["Read", "Bash", "Glob"]
---

# Codex Session Status

Show information about the most recent Codex validation session.

## Find Latest Session

Look for the most recent session directory:
```bash
ls -1td .claude/codex/*/ 2>/dev/null | head -1
```

If no sessions found, tell the user: "No Codex validation sessions found in this project."

## Display Session Info

### Meta.json (if exists)

Read `.claude/codex/<session>/meta.json` and display:
- Iteration count
- Total tokens (input + output)
- Findings history per iteration
- Circuit breaker status
- Elapsed time

### JSONL Events Summary

For each `events-*.jsonl` file in the session directory, run:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh .claude/codex/<session>/events-*.jsonl --progress
```

### Findings Summary

If structured output files exist (`.json`), summarize:
- Total findings by severity
- Total findings by confidence
- Verdict
- Key findings (HIGH severity)

### Debate Artifacts (if debate session)

List which phases completed:
- Phase 1 (independent): claude + codex
- Phase 2 (cross-review): claude + codex
- Phase 3 (meta-review): claude + codex
- Phase 4 (synthesis)

## Format

Present as a concise status report:

```
Codex Session: <session-id>
Mode: plan-validation | code-review | debate
Iterations: 2
Findings: 4 (1 HIGH, 2 MEDIUM, 1 LOW)
Verdict: APPROVE_WITH_CHANGES
Tokens: 31K input / 2.1K output
Time: 45s
Circuit breaker: none triggered
```
