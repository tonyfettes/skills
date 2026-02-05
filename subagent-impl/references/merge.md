# Merge Guide

## 1. Review in Worktree

```bash
cd ./worktrees/<name>
git diff                              # Check changes
# Run project's test commands from CLAUDE.md
```

**Checklist:**
- [ ] Matches requirements
- [ ] Has tests with edge cases
- [ ] Single commit with Co-Authored-By
- [ ] No debug prints, commented code

## 2. Merge

```bash
cd <project-root>
git merge feature/<id>-<name> --no-ff -m "Merge <name>: <description>"
```

## 3. Resolve Conflicts

If conflicts occur:

```bash
git status                            # See conflicted files
grep -n "^<<<<<<" <file>              # Find conflict markers
```

| Pattern | Resolution |
|---------|------------|
| Same function modified | Choose better or combine logic |
| Tests at same location | Keep ALL tests from both |
| Context changes | Keep newer/more complete |

**After resolving:**
```bash
grep -c "<<<<<<" <file>               # Should be 0
# Run project's test commands from CLAUDE.md
git add <file>
git commit -m "Merge <branch>: <desc>

Conflict resolution: <explanation>"
```

## 4. Cleanup

**Immediately after merge:**
```bash
git worktree remove ./worktrees/<name>
git branch -d feature/<id>-<name>
```

## Troubleshooting

| Problem | Resolution |
|---------|------------|
| Tests fail after merge | Run full suite before merge |
| Too many commits | Use `git merge --squash` |
