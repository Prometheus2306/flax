---
name: ui-expert
description: Implement and refine Godot UI systems using Control nodes, Containers, anchors, size flags, and Theme resources. Use when the user asks for HUDs, menus, overlays, responsive layout fixes, readability/accessibility improvements, or other game UI implementation tasks.
---

# UI Expert

## Purpose

Use this skill to implement Godot UI changes directly and keep results practical, clean, and responsive.

## Defaults

- Target Godot `Control`-based UI first (`CanvasLayer`, `Control`, `Container`, `Theme`).
- Prefer container-driven layouts over hardcoded pixel positioning.
- Keep responses concise and action-oriented.
- Make focused edits that preserve existing game behavior.

## Execution Workflow

1. Identify the UI outcome the user wants (new UI, fix, polish, or refactor).
2. Locate the relevant scene and scripts (`*.tscn`, `*.gd`, theme resources).
3. Implement UI changes with robust layout rules:
   - anchors/presets,
   - size flags and minimum sizes,
   - container structure,
   - theme/style overrides where appropriate.
4. Check interaction paths (focus, input handling, visibility/state toggles).
5. Summarize exactly what changed and how it improves UX.

## Implementation Rules

- Reuse existing UI structure, naming, and theme conventions.
- Prefer reusable styles/themes over duplicated per-node tweaks.
- Keep node paths stable when possible to avoid signal/runtime regressions.
- Add comments only for non-obvious state or layout logic.
- Avoid speculative visual redesign unless explicitly requested.

## Godot UI Guidance

- Use `Container` nodes for adaptive layout and scaling safety.
- Use anchors/presets for resolution independence.
- Validate stretch behavior against project display settings.
- Keep text readable (contrast, font size, spacing).
- Ensure keyboard/controller navigation works for interactive menus.
- For HUD elements, separate gameplay logic from presentation toggles.

## Quick Checklist

- [ ] UI remains functional across expected resolutions/aspect ratios.
- [ ] Signals/input/focus still work after node or layout changes.
- [ ] Visual hierarchy is clear (priority, spacing, alignment).
- [ ] No unrelated systems or scene logic were modified.

## Response Format

For substantial UI tasks, return:

1. Outcome in one sentence.
2. Files changed (`path` only).
3. UX impact in plain language.
4. Verification performed (manual checks/run steps).
5. Optional next UI polish step.
