# moonbit skill A/B eval harness

Measures whether the `moonbit` skill actually changes agent behavior, by
running headless agents (claude / codex) on small MoonBit tasks in isolated
sandboxes and grading the results with hidden conformance tests.

One trial = `(task, agent, variant)`:

- **task** — a directory under `tasks/` (see layout below)
- **agent** — `claude` (`claude -p`) or `codex` (`codex exec`)
- **variant** — `control` (no skill) or `skill` (skill injected)

## Run

```sh
# codex only, 1 trial per cell (smoke)
python3 runner.py --run-id smoke1 --agents codex --trials 1

# full: both agents, n=10
python3 runner.py --run-id full1 --agents claude,codex --trials 10 --workers 4

# re-aggregate an existing run
python3 report.py results/full1/results.jsonl
```

Claude auth: fresh `CLAUDE_CONFIG_DIR` per trial has no login. Either
`export ANTHROPIC_API_KEY=...` before running, or log in once into a seed dir
(`CLAUDE_CONFIG_DIR=~/.claude-eval-seed claude` → `/login`) and pass
`--claude-config-seed ~/.claude-eval-seed`.
Codex auth: `~/.codex/auth.json` is copied into each trial's `CODEX_HOME`.

## Subagent mode (claude arm without CLI auth)

Alternative claude arm that runs inside an interactive Claude Code session
(no headless login needed): the session orchestrates one **subagent per
trial** (Agent tool, `model: sonnet`) instead of spawning `claude -p`.

```sh
./prep-subagent-run.sh sub-ab1 3        # sandboxes + per-trial prompt.txt
# ... session spawns one subagent per <trial>/prompt.txt, waits for all ...
python3 grade-run.py /tmp/moonbit-skill-evals/sub-ab1
```

Differences from the CLI arm — **label these rows `claude-sub` and don't pool
them with `claude` CLI rows**:

- **Isolation is instruction-based, not environment-based.** Subagents share
  the session's process, so the session's skills are technically reachable;
  both variants are told "do NOT use the Skill tool", and the treatment gets
  the skill as plain files at `./moonbit-docs/` referenced from the prompt.
  If a control agent disobeys, the bias *shrinks* the measured delta
  (conservative direction), but it's still a weaker guarantee than the CLI
  arm's fake-HOME isolation.
- **This arm measures skill content, not trigger machinery** — the treatment
  prompt explicitly points at the docs, so description-based autotriggering
  is not exercised (the codex/claude CLI arms cover that).
- Per-trial metrics come from the subagent's final-message self-report
  (`done` / `consulted_docs` / `moon_failures_seen`), which is noisier than
  transcript parsing; the orchestrator saves it as `<trial>/report.json` so
  grade-run.py picks it up.

## Isolation (all verified empirically)

- Sandboxes live outside the repo (`--scratch`, default `/tmp/moonbit-skill-evals`),
  so control agents cannot find the skill by walking the repo.
- `HOME` is pointed at an empty dir per trial — **both CLIs discover skills
  via `~/.agents/skills`**, where this skill is globally symlinked; without
  this the control group is contaminated.
- `MOON_HOME` is pinned to the real `~/.moon` so the toolchain and the
  registry cache still resolve under the fake `HOME`.
- Skill injection: claude → `<work>/.claude/skills/moonbit`;
  codex → `<CODEX_HOME>/skills/moonbit`.

## Task layout

```
tasks/<id>/
  prompt.md      # what the agent is asked to do (never names the expected API)
  template/      # moon project the agent starts from (stubs with `...`)
  conformance/   # hidden test package, injected by verify.sh AFTER the agent run
  solution/      # reference solution — used to validate the task, never shipped
  verify.sh      # grades <workdir>: behavioral tests + static checks
  meta.json      # which skill reference this task tests, expected naive failure
```

Design rules learned while building the first three tasks:

- **Conformance tests live in their own package** (`conformance/` with its own
  `moon.pkg`), copied in at verify time. The agent can't see, edit, or break
  their wiring.
- **Fixed harness files are restored before grading** (see
  `async-cancellation-safety/verify.sh` restoring `conn.mbt`) so agents can't
  pass by weakening the test double.
- **Every task is validated in both directions** before use: the reference
  solution must pass verify, and the expected naive solution must fail it —
  ideally failing only the discriminating assertion (e.g. unprotected cleanup
  passes the normal + error paths but fails the cancellation test).
- Verify asserts the *specific* failure signal, not just exit codes, and the
  behavioral trap should be real (UTF-16 `to_bytes()` corrupts CJK bytes;
  cancelled async cleanup drops the END message) rather than a style grep.

## Metrics per trial (`results/<run-id>/results.jsonl`)

- `pass` — verify.sh verdict (primary)
- `skill_loaded` — transcript mentions skill files; separates "didn't trigger"
  from "triggered but didn't help"
- `compile_errors_seen`, `deprecation_warnings_seen`, `moon_invocations` —
  how much the compiler had to teach the agent (skill value often shows up
  here even when pass rates tie)
- `cost_usd`, `turns` (claude), `duration_s`

`manifest.json` records moon/claude/codex versions and the skill's git rev —
deprecation-sensitive tasks drift with the toolchain, so comparisons are only
valid within matching manifests.
