# Prompt Patterns for Codex Validation

## Core Principles

1. **Inline all content** - Codex has issues reading files reliably. ALWAYS paste plan text, code excerpts, and context directly into the prompt. Never say "read file X" or "see plan at path Y". If the prompt exceeds ~6000 words, write the full content to `.claude/codex/prompt-context.md` and tell Codex to read from there — it's inside the project directory and accessible in read-only sandbox mode
2. **Provide full context** - Codex has no prior conversation context. Include everything it needs in the prompt itself
3. **Be specific about what to validate** - Vague prompts produce vague feedback
4. **Request structured output** - Ask for categorized findings with severity and confidence levels
5. **Set the role** - Frame Codex as an independent reviewer, not a collaborator

## Plan Validation Prompt Template

**Note:** Replace all `{placeholders}` with actual content. NEVER replace a placeholder with a file path — always inline the real content.

```
You are an independent technical reviewer. Review the following implementation plan for a feature in this codebase.

## Codebase Context
{Brief description of the project, stack, and relevant architecture. Inline key conventions from CLAUDE.md here — do NOT tell Codex to read CLAUDE.md}

## Feature Requirements
{What the feature should accomplish — full requirements text, not a link}

## Proposed Plan
{The FULL implementation plan with all steps, file changes, code snippets. Paste the entire plan here}

## Relevant Existing Code
{Paste key code excerpts that Codex needs to understand. Format as:}

### src/path/to/file.ts (lines N-M)
\```typescript
{paste actual code here}
\```

## Review Criteria
Evaluate this plan for:
1. **Correctness** - Will this plan actually achieve the requirements?
2. **Completeness** - Are there missing steps, edge cases, or files that need changes?
3. **Architecture** - Does this fit the existing codebase patterns and conventions?
4. **Risks** - What could go wrong? What are the failure modes?
5. **Alternatives** - Are there simpler or better approaches?

## Confidence Rating
Rate each finding's confidence:
- HIGH: You verified it (ran a command, found concrete evidence, or it's a definite bug)
- MEDIUM: Strong reasoning but you didn't verify directly
- LOW: Possible issue but uncertain — style preference, speculative, or based on incomplete info

## Output Format
Respond with a JSON object. Each finding must include:
- severity: CRITICAL, HIGH, MEDIUM, or LOW
- confidence: HIGH, MEDIUM, or LOW
- category: correctness, completeness, architecture, risk, alternative, type_safety, error_handling, performance, security, or convention
- file: the relevant file path (or "general" for cross-cutting)
- line: the relevant line number (or 0 for cross-cutting)
- description: clear explanation of the issue
- suggestion: actionable fix

Set verdict to APPROVE, APPROVE_WITH_CHANGES, or REQUEST_CHANGES.
Include a brief summary of your overall assessment.
```

**Note:** When `--output-schema` is used, the JSON structure is enforced by the schema. When using `codex exec review` (which does not support `--output-schema`), use the text-based format below:

```
For each issue found, provide:
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Confidence**: HIGH / MEDIUM / LOW
- **Category**: correctness / completeness / architecture / risk / alternative / type_safety / error_handling / performance / security / convention
- **Description**: What the issue is
- **Suggestion**: How to address it

End with an overall assessment: APPROVE / APPROVE_WITH_CHANGES / REQUEST_CHANGES
```

## Code Review Prompt Template

```
You are an independent code reviewer. Review the changes in this repository for quality, correctness, and adherence to project conventions.

## Context
{What these changes are for, the feature/bug being addressed}

## Focus Areas
{Specific concerns to look for}

## Review Criteria
1. Logic errors and bugs
2. Edge cases and error handling
3. Type safety and null handling
4. Performance implications
5. Security vulnerabilities
6. Code style and consistency with existing patterns

## Confidence Rating
Rate each finding's confidence:
- HIGH: You verified it (ran a command, found concrete evidence, or it's a definite bug)
- MEDIUM: Strong reasoning but you didn't verify directly
- LOW: Possible issue but uncertain — style preference, speculative, or based on incomplete info

## Output Format
For each issue found:
- **File:Line** - Location
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Confidence**: HIGH / MEDIUM / LOW
- **Issue**: Description
- **Fix**: Suggested correction

End with: APPROVE / APPROVE_WITH_CHANGES / REQUEST_CHANGES
```

## Iteration Prompt Template (Second Round)

```
You are continuing a technical review. In a previous review, you identified these issues:

## Previous Findings
{List of issues from the previous round}

## Responses to Findings
{For each finding: whether it was accepted, rejected with reasoning, or partially addressed}

## Updated Plan/Code
{The revised plan or description of code changes made}

## Task
1. Verify that accepted issues have been properly addressed
2. Evaluate the reasoning for rejected findings - push back if the rejection is wrong
3. Check if new issues were introduced by the changes
4. Provide updated assessment with confidence ratings

End with: APPROVE / APPROVE_WITH_CHANGES / REQUEST_CHANGES
```

## Cross-Review Prompt Template

Used when feeding Claude's evaluation back to Codex for adversarial cross-review.

```
You are participating in a structured code review debate. Another independent reviewer has evaluated your findings and provided their assessment.

## Your Original Findings
{Codex's phase 1 findings — inlined from the structured JSON output}

## Other Reviewer's Evaluation
{Claude's evaluation — inlined from claude-evaluation.md}

## Your Task
For each of your findings that the other reviewer REJECTED:
- If you have counter-evidence, defend your finding with specific proof
- If their reasoning is sound, concede the point

For each of your findings that the other reviewer ACCEPTED:
- Confirm the suggested fix approach is correct
- Flag if you see a better fix

For any new issues the other reviewer raised:
- Evaluate them with the same rigor

Provide your revised findings with updated confidence ratings.
End with: APPROVE / APPROVE_WITH_CHANGES / REQUEST_CHANGES
```

## Debate Phase 2 Prompt Template

Used when Codex critiques Claude's independent findings.

```
You are an independent technical reviewer participating in a debate. Another reviewer independently found these issues in the same codebase:

## Other Reviewer's Findings
{Claude's phase 1 findings — inlined}

## The Code/Plan Under Review
{Inline the relevant code or plan content}

## Your Task
For each finding from the other reviewer:
- **AGREE**: If the issue is valid, explain why with evidence
- **DISAGREE**: If the issue is wrong, provide counter-evidence
- **PARTIALLY_AGREE**: If partially valid, explain what's right and wrong

Also identify any issues the other reviewer MISSED that you found in your own analysis.

Rate each of your assessments with confidence: HIGH / MEDIUM / LOW.
```

## Debate Phase 3 (Meta-Review) Prompt Template

Used when Codex responds to Claude's critique of Codex's findings.

```
You are in the final defense round of a structured review debate.

## Your Original Findings
{Codex's phase 1 findings}

## Critique of Your Findings
{Claude's phase 2 critique — what they agreed/disagreed with}

## Your Task
For each DISAGREEMENT:
- Defend with stronger evidence if you believe you're right
- Concede if the critique is valid

For each AGREEMENT:
- Confirm and note any additional context

Provide your final position on each finding with updated confidence.
End with your final verdict.
```

## Architecture Review Prompt Template

**Note:** Inline the actual code from key files. Do NOT list file paths for Codex to read.

```
You are reviewing the architecture of a proposed feature.

## Existing Patterns (from codebase)
{Paste actual code excerpts showing the patterns Codex needs to understand. Include:}

### src/path/to/pattern-example.ts
\```typescript
{paste the actual code showing the existing pattern}
\```

## Proposed Architecture
{Description of the proposed approach with full detail}

## Questions to Answer
1. Does this follow the existing patterns shown above?
2. Are there existing abstractions that should be reused?
3. Is the module boundary clean?
4. Will this create maintenance burden?

Rate confidence for each assessment: HIGH / MEDIUM / LOW.
Provide specific references to the code shown above in your response.
```

## Tips for Effective Prompts

### DO

- **Inline all plan content and code excerpts** directly in the prompt
- Include relevant conventions from CLAUDE.md (pasted in, not referenced)
- Ask for severity AND confidence ratings to prioritize feedback
- Request structured output (categories, file:line references)
- Include the "why" behind the feature/change

### DON'T

- Tell Codex to "read file X" or "check path Y" — it has issues reading files reliably
- Reference CLAUDE.md or other docs by path — paste the relevant rules inline
- Ask open-ended questions like "what do you think?"
- Include irrelevant context that dilutes the review focus
- Skip specifying the output format (unstructured feedback is hard to process)

## Handling Codex Output

### Parsing JSONL Events

After Codex completes with `--json`, extract the structured output:

```bash
# Extract final structured findings
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh events.jsonl --output

# Get execution summary (token usage, tool calls)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh events.jsonl --progress

# Check for errors
bash ${CLAUDE_PLUGIN_ROOT}/scripts/parse-jsonl.sh events.jsonl --errors
```

### Parsing Structured JSON (from --output-schema)

```bash
# Extract high-severity findings
jq '.findings[] | select(.severity == "CRITICAL" or .severity == "HIGH")' findings.json

# Get verdict
jq -r '.verdict' findings.json

# Count findings by severity
jq '[.findings[].severity] | group_by(.) | map({(.[0]): length}) | add' findings.json

# Filter by confidence
jq '.findings[] | select(.confidence == "HIGH")' findings.json
```

### Evaluating Feedback Quality

Not all Codex feedback is actionable. Filter by:

1. **Specificity** - Does it point to concrete code/plan elements?
2. **Accuracy** - Does the finding match what the code actually does?
3. **Relevance** - Is it about the changes, or general codebase nitpicking?
4. **Actionability** - Is there a clear path to address it?
5. **Confidence** - HIGH confidence findings get priority; LOW confidence gets scrutiny

Dismiss findings that are:

- Generic best-practice advice not specific to this change
- Based on misunderstanding the codebase architecture
- Style preferences that contradict project conventions
- Duplicate findings already covered by existing tests/linting
