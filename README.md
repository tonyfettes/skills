# Skills

A collection of [Agent Skills](https://github.com/vercel-labs/skills) for Claude Code and other coding agents.

## Available Skills

| Skill | Description |
|-------|-------------|
| [moonbit](./moonbit/SKILL.md) | Authoritative MoonBit reference — syntax, project layout, `moon` tooling, C FFI, `.mbtx` scripting. Load before writing any MoonBit code. |
| [rabbita](./rabbita/SKILL.md) | Rabbita (Elm-architecture MoonBit web framework) — pure `update`/`view` rules, effect-package design, model/state-enum design, purity testing. |

## Installation

Install with the [skills](https://github.com/vercel-labs/skills) CLI:

```sh
# install all skills from this repo
npx skills add tonyfettes/skills --all

# or pick one
npx skills add tonyfettes/skills --skill moonbit
```

## Structure

Each skill is a directory containing:
- `SKILL.md` — skill definition with frontmatter (`name`, `description`) and instructions
- `references/` (optional) — supporting documentation routed to from SKILL.md
- `scripts/` (optional) — helper scripts used by the skill
