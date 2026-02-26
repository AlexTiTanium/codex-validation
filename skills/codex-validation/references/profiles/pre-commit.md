# Profile: pre-commit

Diff-focused review for changes about to be committed. Checks the diff only (not the full codebase) for convention compliance, obvious bugs, and commit-readiness.

## Focus Areas
1. Convention compliance with CLAUDE.md / project style guide
2. Obvious bugs introduced in the diff
3. Missing or incorrect type annotations
4. Incomplete error handling in changed code
5. Debug code left in (console.log, TODO, FIXME, commented-out code)
6. Test coverage for changed functionality

## Review Criteria
- Only review lines that changed (the diff), not surrounding code
- Flag debug artifacts and temporary code
- Check naming conventions match project style
- Verify new functions have appropriate error handling
- Note missing tests for new functionality

## Reasoning Effort
medium

## Severity Filter
Report all findings — pre-commit is about catching small issues before they enter history.

## Prompt Injection
```
You are reviewing a diff that is about to be committed. Focus only on the changed lines. Check for: bugs, convention violations, debug code left in, missing error handling, and missing tests. Be practical — this is a pre-commit check, not an architecture review.
```
