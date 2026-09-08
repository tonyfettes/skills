# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Repository Purpose

A collection of Codex skills. Each skill is a directory containing a `SKILL.md` file that defines specialized workflows, knowledge, or tool integrations for Codex.

## Skill Structure

Each skill directory should contain:
- `SKILL.md` - Main skill definition with frontmatter (name, description) and instructions
- `references/` (optional) - Supporting documentation referenced by SKILL.md

## Creating Skills

Use the `skill-creator` skill when creating or updating skills in this repository.

## Commit Convention

```
<type>(<scope>): <description>

Co-Authored-By: Codex Opus 4.5 <noreply@anthropic.com>
```

Types: feat, fix, refactor, test, docs, chore
