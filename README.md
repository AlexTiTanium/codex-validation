# codex-validation

Claude Code plugin for cross-validating plans and code with OpenAI Codex CLI.

## Features

- **Plan Validation** (`/codex:validate`) — Review implementation plans before coding
- **Code Review** (`/codex:review`) — Independent review of uncommitted changes, branches, or commits
- **Adversarial Debate** (`/codex:debate`) — 4-phase structured debate between Claude and Codex
- **Session Status** (`/codex:status`) — View last session results and token costs
- **JSONL Streaming** — Real-time visibility into Codex execution via `--json` event stream
- **Confidence Ratings** — Findings rated by both severity and confidence for smarter triage
- **Circuit Breaker** — Auto-stop on stagnation, issue recycling, or token budget
- **Cross-Review Protocol** — Formal adversarial exchange where each agent critiques the other

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed (`brew install codex`)
- Authenticated via ChatGPT account or API key
- `jq` installed (`brew install jq`)

## Installation

```bash
claude plugins add ~/Projects/codex-validation
```

## Commands

| Command | Description |
|---------|-------------|
| `/codex:review [uncommitted\|branch <base>\|commit <sha>]` | Quick code review |
| `/codex:validate [path-to-plan]` | Plan validation |
| `/codex:debate [uncommitted\|plan <path>\|branch <base>]` | Full adversarial 4-phase review |
| `/codex:status` | Show last session results and costs |

## Agent

The `codex-reviewer` agent can be spawned by other workflows (feature-dev, pr-review) for independent Codex validation without invoking the full skill.

## How It Works

### Quick Review (`/codex:review`)

1. Assess scope of changes
2. For 3+ files, split into parallel correctness + architecture reviews
3. Run Codex in background with JSONL streaming
4. Extract and evaluate findings with confidence-aware triage
5. Iterate with cross-review protocol if needed (max 3 rounds)

### Plan Validation (`/codex:validate`)

1. Gather plan content and relevant code
2. Construct focused prompt with inline content
3. Run Codex with structured output schema
4. Evaluate findings, iterate if needed
5. Present validated plan with accepted changes

### Adversarial Debate (`/codex:debate`)

4-phase structured debate:
1. **Independent Review** — Claude and Codex review separately (parallel)
2. **Cross-Review** — Each critiques the other's findings (parallel)
3. **Meta-Review** — Each defends or concedes (parallel)
4. **Synthesis** — Claude merges all artifacts into final verdict

### Circuit Breaker

Prevents infinite loops and runaway costs:
- **Stagnation**: 2+ rounds with 0 accepted findings → stop
- **Issue Recycling**: Same finding in 2+ rounds → escalate to user
- **Token Budget**: 100K cumulative input tokens → stop
- **Timeout**: 5 minutes per Codex call → kill and report

## Configuration

Exchange files go to `.claude/codex/<session-id>/` in the project root (gitignored, no permission prompts).

Codex configuration is at `~/.codex/config.toml`. The plugin respects your model and reasoning effort settings.

## Hooks

Hooks are empty by default. To enable auto-review triggers, edit `hooks/hooks.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "If code was modified during this session and no Codex review was performed, suggest running /codex:review to the user.",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## File Structure

```
.claude-plugin/plugin.json      Plugin manifest
commands/                        Slash commands (/codex:*)
agents/codex-reviewer.md        Spawnable review agent
skills/codex-validation/         Core knowledge base
  SKILL.md                       Reference documentation
  references/                    CLI reference, prompt patterns, output schema
hooks/hooks.json                 Optional auto-review hooks
scripts/                         Bash wrappers
  codex-validate.sh              Plan/review/resume/exec wrapper
  codex-review-diff.sh           Git diff review wrapper
  parse-jsonl.sh                 JSONL event parser
```
