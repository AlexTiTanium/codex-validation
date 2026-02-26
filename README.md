# codex

Claude Code plugin for cross-validating plans and code with OpenAI Codex CLI.

## Commands

| Command | Description |
|---------|-------------|
| `/codex:review [scope] [--profile <name>] [--persona <name>] [--fix]` | Pair review — Claude and Codex independently review, then cross-validate each other |
| `/codex:validate [path] [--profile <name>]` | Plan validation — Codex reviews your plan before you code |
| `/codex:debate [scope] [--persona <name>]` | Adversarial debate — back-and-forth with internet research to prove positions |

**Scope options:** `uncommitted` (default), `branch <base>`, `commit <sha>`, `plan <path>`

## How It Works

### Review (Pair)
Both Claude and Codex review your code independently, then cross-validate each other's findings. Issues found by both reviewers are high-confidence. Disagreements are presented for your decision.

### Validate
Codex independently reviews your implementation plan before you start coding. Catches missing steps, edge cases, and architectural issues early.

### Debate
4-phase adversarial debate: independent review → cross-critique → defense → synthesis. Both sides use internet research (docs, RFCs, benchmarks) to back their positions.

## Review Profiles

| Profile | Focus |
|---------|-------|
| `security-audit` | OWASP Top 10, injection, auth, crypto |
| `performance` | N+1 queries, memory, algorithmic complexity |
| `quick-scan` | CRITICAL/HIGH only, fast turnaround |
| `pre-commit` | Diff-only, conventions, debug code |
| `api-review` | Contracts, breaking changes, versioning |

## Personas

| Persona | Mindset |
|---------|---------|
| `senior-engineer` | Pragmatic, production-readiness focused |
| `security-researcher` | Adversarial, attack surface focused |
| `performance-engineer` | Quantitative, latency/memory focused |
| `junior-mentor` | Educational, explains principles |
| `devil-advocate` | Contrarian, challenges every assumption |

Profiles and personas compose: `--profile security-audit --persona devil-advocate`

Custom personas: create `.codex-personas.md` at project root.

## Policy Engine

Optional `.codex-policy.json` at project root:

```json
{
  "blocking": ["security", "correctness"],
  "warning": ["convention", "alternative"],
  "auto_dismiss": { "max_severity": "LOW", "max_confidence": "LOW" },
  "non_overridable": ["CRITICAL+security", "CRITICAL+correctness"]
}
```

CRITICAL security/correctness findings can never be auto-dismissed.

## Auto-Fix

`/codex:review --fix` auto-fixes accepted MECHANICAL findings:
- Creates git branch before changes
- Verifies fixes with Codex
- Rollback on failed verification
- `--fix --dry-run` to preview

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed (`brew install codex`)
- Authenticated via ChatGPT account or API key
- `jq` installed (`brew install jq`)

## Installation

```bash
claude plugins add ~/Projects/codex-validation
```

## Agent

The `codex-reviewer` agent can be spawned by other workflows (feature-dev, pr-review) for independent Codex validation without invoking the full skill.

## File Structure

```
.claude-plugin/plugin.json         Plugin manifest
commands/
  review.md                         /codex:review (pair review with --profile, --persona, --fix)
  validate.md                       /codex:validate (plan validation with --profile)
  debate.md                         /codex:debate (adversarial debate with internet research)
agents/codex-reviewer.md            Spawnable review agent
skills/codex-validation/
  SKILL.md                          Core knowledge base
  references/
    codex-cli-reference.md          CLI flags and configuration
    prompt-patterns.md              Prompt templates
    review-output-schema.json       JSON Schema for structured output
    severity-taxonomy.md            Severity/fixability definitions
    policy-schema.json              Schema for .codex-policy.json
    profiles/                       Review profiles (5 built-in)
    personas/                       Reviewer personas (5 built-in)
scripts/
  codex-validate.sh                 Plan/review wrapper
  codex-review-diff.sh              Git diff review wrapper
  parse-jsonl.sh                    JSONL event parser
```
