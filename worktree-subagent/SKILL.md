---
name: worktree-subagent
description: Guide for spawning and managing subagents using git worktrees for isolated implementation tasks.
---

# Subagent Workflow

**Main agent role**: Planner, monitor, reviewer, integrator. Spawn subagents for implementation.

## Subagent Types

| Type | Use Case |
|------|----------|
| `general-purpose` | Implementation tasks, bug fixes, features |
| `Explore` | Understanding codebase, finding patterns |
| `Plan` | Designing implementation approach |
| `Bash` | Git operations, running commands |

---

## 1. Prepare

Before spawning, ensure:
- [ ] Scope is specific (not "improve X" but "implement Y in X")
- [ ] Acceptance criteria are clear
- [ ] No blocking dependencies
- [ ] Local changes committed (worktrees created from HEAD)

## 2. Create Worktree

```bash
mkdir -p worktrees
git worktree add ./worktrees/<name> -b feature/<id>-<name>
```

## 3. Spawn Subagent

Use the Task tool with `subagent_type="general-purpose"` and `run_in_background=true`:

```
You are working in: <worktree-path>

## Task
<description>

## Context
- Read CLAUDE.md for build/test/format commands
- Reference: <key files to read>
- Follow patterns in: <similar modules>

## Requirements
- [ ] <Specific requirement 1>
- [ ] <Specific requirement 2>
- [ ] Build and tests pass
- [ ] Code follows existing patterns
- [ ] No debug prints, commented code, or unused imports

## Commit
Single commit when done:
git commit -m "<type>(<scope>): <description>

<why this change>

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"

Types: feat, fix, refactor, test, docs, chore

## Anti-patterns to avoid
- Over-engineering (abstractions for single use, unrequested features)
- Under-testing (happy path only)
- Scope creep (changes outside task)
```

## 4. Monitor

```bash
tail -50 /path/to/output-file
```

| Signal | Action |
|--------|--------|
| Making progress | Let continue |
| Same error 3+ times | Resume with guidance |
| Wrong approach | Abort and restart |

**Resume**: `Task tool with resume="<agent-id>"` - agent keeps full context.

See [references/monitor.md](./references/monitor.md) for detailed intervention guidance.

## 5. Merge & Cleanup

```bash
# Review in worktree
cd ./worktrees/<name>
git diff
# Run project's test commands from CLAUDE.md

# Merge from project root
cd <project-root>
git merge feature/<id>-<name> --no-ff -m "Merge <name>: <description>"

# Cleanup
git worktree remove ./worktrees/<name>
git branch -d feature/<id>-<name>
```

**Review checklist**:
- [ ] Matches requirements
- [ ] Has tests
- [ ] Single commit with Co-Authored-By

See [references/merge.md](./references/merge.md) for conflict resolution.

---

## Troubleshooting

| Problem | Resolution |
|---------|------------|
| Wrong architecture | Abort, restart with clearer prompt |
| Tests fail after merge | Run full suite before merge |
| Too many commits | Use `git merge --squash` |
