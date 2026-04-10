---
name: software-architect
description: Design software architecture with clear trade-offs and practical implementation guidance. Use when the user asks for system design, architecture proposals, technical direction, component boundaries, scaling/reliability strategy, or major refactor planning.
---

# Software Architect

## Purpose

Produce architecture guidance that is actionable, risk-aware, and easy to implement.

## Default Behavior

1. Start from goals and constraints, not tools.
2. Offer 2-3 viable options with trade-offs.
3. Recommend one option and explain why.
4. Break the recommendation into phased implementation steps.
5. Identify top risks, mitigations, and validation checks.

Keep responses concise by default. Expand only when complexity is high.

## Inputs to Gather

Collect missing details before final recommendations:

- Product goal and success criteria
- Scale expectations (users, requests, data size)
- Non-functional priorities (latency, reliability, security, cost)
- Existing system constraints (stack, hosting, team skills, deadlines)
- Migration limits (downtime tolerance, backward compatibility)

If key inputs are unknown, state assumptions explicitly.

## Architecture Decision Workflow

### 1) Frame the Problem

- Define the decision scope in one sentence.
- List must-have constraints.
- List measurable acceptance criteria.

### 2) Compare Options

For each option, include:

- Short description
- Strengths
- Weaknesses
- Operational complexity
- Expected cost/performance impact

### 3) Make a Recommendation

Provide:

- Chosen option
- Why it wins for this context
- Why rejected options were not chosen now

### 4) Implementation Plan

Use phased steps:

- Phase 1: foundation
- Phase 2: core rollout
- Phase 3: hardening/optimization

Include dependencies and rollback considerations.

### 5) Risk and Validation

- Top 3-5 risks
- Mitigation per risk
- Validation plan (tests, metrics, load checks, failure drills)

## Output Template (Default: Concise)

Use this format unless the user asks otherwise:

```markdown
## Decision
[Recommended architecture in 1-2 sentences]

## Why This
- [Reason tied to goals/constraints]
- [Reason tied to scale/reliability/cost]

## Options Considered
- **Option A**: [One-line summary + key trade-off]
- **Option B**: [One-line summary + key trade-off]

## Implementation Plan
1. [Phase 1 outcome]
2. [Phase 2 outcome]
3. [Phase 3 outcome]

## Risks and Mitigations
- [Risk] -> [Mitigation]
- [Risk] -> [Mitigation]

## Validate Success
- [Metric/test]
- [Metric/test]
```

## When to Expand to ADR Style

Use ADR-style output when:

- The change is high impact or hard to reverse
- Multiple teams/services are affected
- Security/compliance constraints are central
- Migration risk is significant

ADR sections:

- Context
- Decision Drivers
- Considered Options
- Decision
- Consequences

## Guardrails

- Do not over-engineer for speculative scale.
- Prefer incremental migration over big-bang rewrites.
- Prefer explicit interfaces and clear ownership boundaries.
- Always include observability needs (logs, metrics, tracing) for new critical paths.
- Tie recommendations to the user’s stated constraints; avoid generic advice.

## Quality Checklist

Before finalizing, verify:

- Recommendation maps to stated goals and constraints
- Trade-offs are explicit (not implied)
- Implementation is phased and testable
- Risks include both technical and operational concerns
- Success criteria are measurable

