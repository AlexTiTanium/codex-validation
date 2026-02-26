# Severity & Fixability Taxonomy

Unified contract for how severity, confidence, and fixability are interpreted across all plugin features.

## Severity Levels

| Level | Definition | Examples |
|-------|-----------|----------|
| **CRITICAL** | Will cause data loss, security breach, or system failure in production | SQL injection, auth bypass, data corruption, infinite loop on hot path |
| **HIGH** | Will cause incorrect behavior or significant degradation | Logic error in business rule, missing error handling on external call, race condition |
| **MEDIUM** | May cause issues under specific conditions or reduces maintainability | Missing edge case handling, suboptimal algorithm, unclear API contract |
| **LOW** | Minor improvement or style concern | Naming convention, minor refactor opportunity, documentation gap |

## Severity Semantics by Feature

| Feature | CRITICAL | HIGH | MEDIUM | LOW |
|---------|----------|------|--------|-----|
| **Policy Engine** | Always blocking (non-overridable) | Blocking by default | Warning by default | Warning by default |
| **Auto-Fix** | Never auto-fix (requires human review) | Auto-fix if MECHANICAL + HIGH confidence | Auto-fix if MECHANICAL | Auto-fix if MECHANICAL |
| **Dedup Priority** | Highest priority in merge (always preserved) | High priority | Standard | Standard |
| **Pair Review** | CONFIRMED even if only one found it | Needs cross-validation | Needs cross-validation | Present but don't block |

## Confidence Levels

| Level | Definition | When to Use |
|-------|-----------|-------------|
| **HIGH** | Verified with concrete evidence | Compile error, test failure, confirmed by running code, definite bug |
| **MEDIUM** | Sound reasoning, not directly verified | Strong logical deduction, pattern-based, similar to known issues |
| **LOW** | Speculative or uncertain | Style preference, might-be-an-issue, based on incomplete information |

## Fixability Classification

Used by `/codex:review --fix` to determine which findings can be automatically applied.

| Classification | Definition | Examples | Auto-Fix? |
|---------------|-----------|----------|-----------|
| **MECHANICAL** | Can be applied as a deterministic code change | Add null check, fix type annotation, add missing import, rename variable, add error return | Yes |
| **GUIDANCE** | Requires human judgment to implement correctly | Improve error message wording, add validation (but what rules?), optimize query (but how?) | No — present as recommendation |
| **ARCHITECTURAL** | Requires redesign or plan revision | Change module boundary, restructure data flow, split service, change API contract | No — present as recommendation |

### Fixability Heuristics

To classify a finding's fixability:

1. **MECHANICAL** if the suggestion is a specific code change with an unambiguous before/after
2. **GUIDANCE** if the suggestion describes what to do but not exactly how (multiple valid implementations)
3. **ARCHITECTURAL** if the suggestion involves changes to more than 3 files or changes interfaces/contracts

## Precedence Rules

When multiple features influence review behavior, apply in this order:

```
Policy Engine (project-level rules)
  ↓ overrides
Review Profile (focus areas and criteria)
  ↓ overrides
Custom Persona (reviewer role and mindset)
  ↓ overrides
Default behavior (hardcoded in SKILL.md)
```

**Conflict resolution:**
- Policy blocking rules always win over profile/persona preferences
- Profile severity filters are applied after policy (policy may override the filter)
- Persona changes only the reviewer role framing, never overrides severity classification
- Print the resolved effective configuration at command start when multiple layers are active
