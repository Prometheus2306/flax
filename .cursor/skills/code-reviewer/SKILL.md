---
name: code-reviewer
description: Review code changes for bugs, regressions, and maintainability with a balanced signal-first approach. Use when reviewing pull requests, diffs, or when the user asks for a code review.
---

# Code Reviewer

## Purpose

Provide high-signal, findings-first code reviews that prioritize correctness, regressions, and security before style.

## When To Apply

Use this skill when:
- The user asks for a "review" of code, PRs, or diffs.
- The user asks for risks, regressions, or test gap analysis.
- You need structured feedback on changed files.

## Review Priorities (Balanced)

Review in this order:
1. Correctness and behavior changes
2. Regressions and edge cases
3. Security and data safety risks
4. Performance issues that are likely user-impacting
5. Maintainability/readability concerns

Avoid low-value style nitpicks unless they hide a real defect.

## Workflow

1. Identify scope of change (files, diffs, and intent).
2. Understand expected behavior from code context.
3. List concrete findings with evidence.
4. Note missing or weak test coverage.
5. Provide a short risk summary and recommended next actions.

## Output Format (Findings First)

Always present findings first, ordered by severity:

- **Critical**: Must fix before merge; likely bug, regression, or security issue.
- **High**: Significant risk; should be fixed before merge.
- **Medium**: Important improvement; can be fixed now or tracked.
- **Low**: Minor improvement; optional unless requested.

For each finding include:
- What is wrong
- Why it matters
- Where it appears (file or symbol path)
- Recommended fix direction

If there are no findings, state:
- "No critical issues found."
- Any residual risks or testing gaps that still exist.

## Test Gap Checklist

Check whether changes include enough coverage for:
- Happy path behavior
- Edge/error paths
- Regressions for previously working behavior
- Security-sensitive paths where relevant

## Guardrails

- Do not invent bugs without code evidence.
- Do not block on personal style preferences.
- Prefer concise, actionable feedback over broad commentary.
- If assumptions are required, label them clearly.
