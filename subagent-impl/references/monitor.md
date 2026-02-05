# Monitoring Guide

## 1. Check Progress

```bash
tail -50 /path/to/output-file          # Recent output
tail -f /path/to/output-file           # Live follow
grep -i "error\|fail" /path/to/output  # Find errors
```

## 2. Decide Action

| Signal | Severity | Action |
|--------|----------|--------|
| Same error 3+ times | High | Resume with fix |
| Wrong file modified | High | Abort and restart |
| Unrelated changes | Medium | Resume with reminder |
| Slow but progressing | Low | Let continue |
| Build passing, iterating | Low | Let continue |

## 3. Intervene

### Resume with Guidance

Use Task tool's `resume` parameter - agent keeps full context.

```
Task tool with resume="<agent-id>":
"<specific guidance>"
```

**Example scenarios:**

| Problem | Guidance Template |
|---------|------------------|
| Type error loop | "The error is because X expects Y. Change Z. See pattern in <file>." |
| Wrong files | "Focus only on: <files>. Do not touch: <other files>." |
| Over-engineering | "Remove the abstraction. Only implement: <requirements>." |
| Missing tests | "Add tests for: empty input, errors, boundaries. See <test-file>." |

### Abort and Restart

```bash
git worktree remove ./worktrees/<name> --force
git worktree add ./worktrees/<name> -b feature/<id>-<name>
```

Use when: fundamental misunderstanding, wrong architecture, too messy to salvage.

### Take Over Manually

Use when: nearly done, you know the fix, subagent time > manual time.

## 4. While Waiting

**Productive tasks:**
- Update documentation
- Clean up completed worktrees
- Spawn parallel agents
- Plan next batch of work

**Track progress** with task tools:
- `TaskCreate` - subtasks at planning
- `TaskUpdate` - mark in_progress/completed
- `TaskList` - check remaining work
