# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A collection of Claude Code skills. Each skill is a directory containing a `SKILL.md` file that defines specialized workflows, knowledge, or tool integrations for Claude Code.

## Skill Structure

Each skill directory should contain:
- `SKILL.md` - Main skill definition with frontmatter (name, description) and instructions
- `references/` (optional) - Supporting documentation referenced by SKILL.md

## Creating Skills

Create or update skills by editing `SKILL.md` and `references/` files directly, following the structure above and the conventions already present in the skill being modified. The `skill-creator` skill can help scaffold new skills when available, but it is not required.

## Commit Convention

```
<type>(<scope>): <description>

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

Types: feat, fix, refactor, test, docs, chore
