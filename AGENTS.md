# AGENTS.md

Guidance for coding agents (Claude Code, Codex, and others) working in this
repository. `CLAUDE.md` is a symlink to this file.

## Repository Purpose

A collection of agent skills. Each skill is a directory containing a
`SKILL.md` file that defines specialized workflows, knowledge, or tool
integrations for an agent.

## Skill Structure

Each skill directory should contain:
- `SKILL.md` - Main skill definition with frontmatter (name, description) and instructions
- `references/` (optional) - Supporting documentation referenced by SKILL.md

## Creating Skills

Create or update skills by editing `SKILL.md` and `references/` files
directly, following the structure above and the conventions already present in
the skill being modified. A skill-creation skill (such as `skill-creator`) can
help scaffold new skills when available, but it is not required.

## Commit Convention

```
<type>(<scope>): <description>

Co-Authored-By: <the model that made the change> <its noreply address>
```

Types: feat, fix, refactor, test, docs, chore. The scope is the skill's
directory name (e.g. `docs(moonbit): ...`). Credit the model that actually made
the change, not a fixed name.
