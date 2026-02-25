# Codex CLI Reference

## Installation Verification

Codex CLI is installed at `/opt/homebrew/bin/codex` via Homebrew cask.
Configuration lives at `~/.codex/config.toml`.

## Non-Interactive Execution (`codex exec`)

The primary interface for programmatic use. Runs Codex as a headless agent that reads the repo, processes a prompt, and returns results to stdout.

### Core Command Pattern

```bash
codex exec [OPTIONS] "PROMPT"
```

Or via stdin (preferred for large prompts — avoids shell escaping issues):

```bash
cat .claude/codex/prompt.md | codex exec [OPTIONS] -
```

### Flag Availability by Subcommand

Not all flags work on every subcommand. Using unsupported flags causes errors.

| Flag | `exec` | `exec review` | `exec resume` |
| --- | --- | --- | --- |
| `-c, --config key=value` | yes | yes | yes |
| `-m, --model MODEL` | yes | yes | yes |
| `-o, --output-last-message FILE` | yes | **no** | **no** |
| `--output-schema FILE` | yes | **no** | **no** |
| `-s, --sandbox MODE` | yes | **no** | **no** |
| `-C, --cd DIR` | yes | **no** | **no** |
| `--ephemeral` | yes | yes | yes |
| `--json` | yes | yes | yes |
| `--full-auto` | yes | yes | yes |
| `--skip-git-repo-check` | yes | yes | yes |
| `-i, --image FILE` | yes | **no** | yes |
| `--last` | **no** | **no** | yes |
| `--uncommitted / --base / --commit` | **no** | yes | **no** |
| `--title TITLE` | **no** | yes | **no** |

### `codex exec` Flags

| Flag | Description |
| --- | --- |
| `-o, --output-last-message FILE` | Write the agent's final message to a file (critical for capturing clean output) |
| `--output-schema FILE` | Path to a JSON Schema file — enforces structured output from the model |
| `--ephemeral` | Run without persisting session files to disk (clean runs) |
| `--sandbox read-only` | Read-only sandbox — agent can read files but not modify anything |
| `--sandbox workspace-write` | Agent can read and write within the workspace |
| `-C, --cd DIR` | Set working directory for the agent |
| `-m, --model MODEL` | Override the default model |
| `-c, --config key=value` | Override a config.toml value (e.g., `-c model_reasoning_effort="medium"`) |
| `--json` | Print events as newline-delimited JSON (JSONL) for structured parsing |
| `--full-auto` | Low-friction mode: workspace-write + on-request approvals |
| `--skip-git-repo-check` | Allow running outside a Git repository |

### JSONL Event Streaming (`--json`)

When `--json` is enabled, stdout becomes a JSONL event stream. Each line is a valid JSON object.

**Event types:**
- `thread.started` — Session initialization
- `turn.started` — New agent turn begins
- `turn.completed` — Turn finished (includes `usage` with token counts)
- `turn.failed` — Turn encountered error
- `item.started` — Item begins processing
- `item.completed` — Item finished
- `error` — System error

**Item types within events:**
- `agent_message` — Text responses from agent (final output)
- `reasoning` — Internal reasoning traces
- `command_execution` — Shell command runs
- `file_changes` — Modifications to tracked files
- `mcp_tool_call` — Model Context Protocol tool invocation
- `web_search` — Search queries executed

**Combining with other flags:**
- `--json` + `--output-schema` — Schema shapes the final `agent_message` content as JSON; JSONL wraps all events
- `--json` replaces `-o` — Final message is in the JSONL stream (extract with `parse-jsonl.sh --output`)
- Only protocol events go to stdout; warnings/config go to stderr

**Parsing example:**
```bash
# Extract final output from JSONL
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh events.jsonl --output

# Get progress summary
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh events.jsonl --progress

# Process events with jq
codex exec --json "prompt" | while read -r line; do echo "$line" | jq .; done
```

### `codex exec review` Flags

Built-in code review with git integration. Does NOT support `-o`, `--output-schema`, `--sandbox`, or `-C`.

| Flag | Description |
| --- | --- |
| `--uncommitted` | Review staged, unstaged, and untracked changes |
| `--base BRANCH` | Review changes against a specific base branch |
| `--commit SHA` | Review changes introduced by a specific commit |
| `--title TITLE` | Optional commit title for the review summary |
| `-m, --model MODEL` | Override the default model |
| `-c, --config key=value` | Override a config.toml value |
| `--ephemeral` | Disable session persistence |
| `--json` | JSONL event streaming |

To capture review output, use `--json 2>&1 | tee events.jsonl`.

### `codex exec resume` Flags

Resume a prior session. Does NOT support `-o`, `--output-schema`, `--sandbox`, or `-C`.

| Flag | Description |
| --- | --- |
| `--last` | Resume the most recent session |
| `-m, --model MODEL` | Override the default model |
| `-c, --config key=value` | Override a config.toml value |
| `--ephemeral` | Disable session persistence |
| `--json` | JSONL event streaming |

### Session Resume (for Multi-Round Validation)

Resume a prior non-interactive session with full context (transcript, plan history, approvals):

```bash
# Resume most recent session with JSONL streaming
codex exec resume --json --last "follow-up prompt" | tee events-resume.jsonl

# Resume a specific session by ID
codex exec resume --json SESSION_ID "follow-up prompt" | tee events-resume.jsonl
```

**Key behavior:**
- Resumed sessions keep the **entire original transcript** — Codex sees all prior exchanges
- Only the follow-up prompt (iteration delta) needs to be sent, not the full context again
- Sessions are saved to `~/.codex/sessions/` as JSONL files
- `--ephemeral` prevents session saving — do NOT use it on the first run if you plan to iterate
- `--last` selects the most recent session from the current working directory

### Structured Output (`--output-schema`)

Available on `codex exec` only (not review or resume). Enforces a JSON Schema on the model's response.

```bash
codex exec --json --output-schema ./references/review-output-schema.json "review prompt" | tee events.jsonl
```

The final `agent_message` in the JSONL stream contains valid JSON matching the schema. Extract with `parse-jsonl.sh --output`.

### Model Selection

| Model | Best For | Notes |
| --- | --- | --- |
| `gpt-5.3-codex` | General plan validation, architecture review | Default in config.toml |
| `gpt-5.2-codex` | Code review, bug detection | Tuned for code review accuracy |

Override via environment variables in wrapper scripts:
- `CODEX_MODEL` — Default model for all modes
- `CODEX_REVIEW_MODEL` — Override model specifically for review mode (falls back to `CODEX_MODEL`)

### Reasoning Effort

There is no `--reasoning-effort` CLI flag. Override via `-c` config flag:

| Method | Example |
| --- | --- |
| **CLI override** | `-c model_reasoning_effort="medium"` |
| **Config file** | `model_reasoning_effort = "medium"` in `~/.codex/config.toml` |
| **Script env var** | `CODEX_REASONING_EFFORT=medium` (scripts translate to `-c` flag) |

Valid values: `low`, `medium`, `high`, `xhigh`. Default for validation workflows: **medium**.

### Timeout Considerations

- Codex exec has no built-in timeout flag
- For plan reviews, expect 30-120 seconds depending on prompt complexity
- For code reviews, expect 60-180 seconds depending on diff size
- Use Bash tool timeout parameter (up to 600000ms) to prevent hangs
- Codex can hang after `tsc --noEmit` in long sessions — may need kill + retry

### Safety Notes

- `--sandbox read-only` is the safest mode — agent cannot modify files
- `--ephemeral` prevents session persistence (clean, stateless runs)
- Never use `--dangerously-bypass-approvals-and-sandbox` in validation workflows
- The `--full-auto` flag enables file writes — only use when Codex needs to demonstrate fixes

### Current Config (from ~/.codex/config.toml)

```toml
model = "gpt-5.3-codex"
model_reasoning_effort = "xhigh"
personality = "pragmatic"
```
