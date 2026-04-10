---
name: coder
description: Implement requested code changes end-to-end in Godot GDScript projects with concise, practical explanations. Use for coding tasks such as implementing features, fixing bugs, refactoring, and updating scripts in this repository.
---

# Coder

## Purpose

Use this skill to execute coding requests directly with a Godot-first workflow:
- Make the code change.
- Validate it.
- Explain what changed and why.

## Defaults

- Prioritize `*.gd` and Godot project structure.
- Be concise and practical in user-facing responses.
- Favor small, targeted edits over broad rewrites.
- Preserve existing behavior unless the request requires behavior changes.

## Execution Workflow

1. Clarify the concrete outcome from the user request.
2. Inspect only the relevant files and symbols.
3. Implement changes directly in code.
4. Run lightweight verification where possible (lint/tests/runtime checks).
5. Report results with:
   - what changed,
   - why it changed,
   - any follow-up actions.

## Implementation Rules

- Keep naming and style consistent with nearby project code.
- Reuse existing helpers/signals/patterns before introducing new abstractions.
- Add comments only where logic is non-obvious.
- Avoid speculative refactors unless explicitly requested.
- If blocked by missing context, ask one focused question and continue immediately after.

## Godot / GDScript Guidance

- Prefer scene/script compatibility over cleverness.
- Keep node-path interactions explicit and robust.
- Handle null/invalid node references defensively when touching runtime paths.
- Preserve signal contracts and exported variable expectations.
- For gameplay tweaks, keep tuning values easy to locate and adjust.

## Verification Checklist

- [ ] Script parses without introducing syntax errors.
- [ ] Changed logic paths are covered by a quick sanity check.
- [ ] No unrelated files were modified.
- [ ] User-facing summary includes key outcomes and caveats.

## Response Format

Use this output shape for substantial tasks:

1. Short outcome statement.
2. Files changed (`path` only).
3. Behavior impact (before/after in plain language).
4. Verification performed.
5. Optional next step (test/run/commit).
