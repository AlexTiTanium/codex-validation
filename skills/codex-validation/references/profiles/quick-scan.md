# Profile: quick-scan

Fast, lightweight review focusing only on critical and high-severity issues. Use for rapid iteration when you want quick feedback without a full review.

## Focus Areas
1. Definite bugs and logic errors
2. Security vulnerabilities
3. Missing error handling on critical paths
4. Type errors and null safety issues

## Review Criteria
- Only report issues that would cause runtime failures, data loss, or security breaches
- Skip style, convention, architecture, and minor improvement suggestions
- Be concise — one sentence per finding

## Reasoning Effort
medium

## Severity Filter
Report CRITICAL and HIGH only. Skip MEDIUM and LOW.

## Prompt Injection
```
You are doing a quick scan for critical issues only. Be fast and concise. Report only definite bugs, security vulnerabilities, and issues that would cause failures in production. Skip style suggestions, convention issues, and minor improvements. One sentence per finding.
```
