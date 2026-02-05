---
name: subagent-plan
description: Guide for structuring plans that leverage subagent parallelization.
---

# Structuring Plans for Subagent Execution

When planning tasks that can benefit from parallel execution, structure your plan
so act-mode Claude can spawn subagents effectively.

## When to Use Subagents

- Multiple independent implementation tasks
- Tasks that can run in isolated worktrees
- Work that benefits from parallel execution

## Plan File Structure

**CRITICAL**: Start with skill loading instruction:

```
## Prerequisites
Load the subagent-impl skill for implementation guidance before starting.
```

**Task table format**:

| ID | Task | Worktree | Dependencies | Acceptance Criteria |
|----|------|----------|--------------|---------------------|
| 1  | Implement feature X | feature-x | none | Tests pass, follows patterns |
| 2  | Add tests for Y | tests-y | none | Coverage for edge cases |
| 3  | Integrate X and Y | integrate | 1, 2 | Full suite passes |

## Task Breakdown Guidelines

- Each task should be completable in one worktree
- Specify clear, verifiable acceptance criteria
- Identify dependencies (what must complete first)
- Include context: key files to read, patterns to follow

## Example Plan Section

```markdown
## Prerequisites
Load the subagent-impl skill for implementation guidance before starting.

## Tasks

| ID | Task | Worktree | Deps | Criteria |
|----|------|----------|------|----------|
| 1  | Add auth middleware | auth | none | Validates tokens, returns 401 on failure |
| 2  | Add rate limiting | rate-limit | none | 100 req/min per IP |
| 3  | Integration tests | tests | 1,2 | Both features work together |

## Execution Order
1. Spawn tasks 1 and 2 in parallel (no dependencies)
2. Wait for both to complete
3. Spawn task 3 after merging 1 and 2
```
