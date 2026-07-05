#!/bin/bash
# prep-subagent-run.sh <run-id> [trials=3] [scratch=/tmp/moonbit-skill-evals]
#
# Prepares sandboxes + per-trial prompt files for the SUBAGENT mode (see
# README "Subagent mode"). The orchestrating Claude session then spawns one
# subagent per prompt file (model: sonnet) and finally runs grade-run.py.
set -euo pipefail
RUN_ID="${1:?usage: prep-subagent-run.sh <run-id> [trials] [scratch]}"
TRIALS="${2:-3}"
SCRATCH="${3:-/tmp/moonbit-skill-evals}"
HARNESS="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$HARNESS/../../moonbit"
BASE="$SCRATCH/$RUN_ID"

rm -rf "$BASE" && mkdir -p "$BASE"

CONTROL_RULES="RULES: Work ONLY inside that directory — never read or write any file outside it. Do NOT use the Skill tool and do not load any skills. Rely only on your own MoonBit knowledge and the files inside the project."
SKILL_RULES="RULES: Work ONLY inside that directory — never read or write any file outside it. Do NOT use the Skill tool and do not load any skills. The project ships MoonBit reference documentation at ./moonbit-docs/ (SKILL.md plus references/): read ./moonbit-docs/SKILL.md first and consult the relevant reference files before writing any MoonBit code."
FINAL='FINAL MESSAGE: reply with exactly one JSON object, no other text: {"done": <bool>, "consulted_docs": <bool>, "moon_failures_seen": <int, number of times a moon check/test/build run reported errors or test failures during your work>, "notes": "<max 200 chars>"}'

for task_dir in "$HARNESS"/tasks/*/; do
  task="$(basename "$task_dir")"
  for variant in control skill; do
    for ((i = 0; i < TRIALS; i++)); do
      name="$task--sub--$variant--$(printf '%02d' "$i")"
      d="$BASE/$name"
      mkdir -p "$d"
      cp -R "$task_dir/template" "$d/work"
      rules="$CONTROL_RULES"
      if [ "$variant" = "skill" ]; then
        mkdir -p "$d/work/moonbit-docs"
        cp -R "$SKILL_SRC/SKILL.md" "$SKILL_SRC/references" "$d/work/moonbit-docs/"
        rules="$SKILL_RULES"
      fi
      {
        echo "Complete a MoonBit coding task in the directory $d/work (cd there first; all paths below are relative to it)."
        echo
        echo "$rules"
        echo
        echo "TASK:"
        cat "$task_dir/prompt.md"
        echo
        echo "$FINAL"
      } > "$d/prompt.txt"
    done
  done
done

echo "prepared $(ls "$BASE" | wc -l | tr -d ' ') trials under $BASE"
echo "spawn one subagent per */prompt.txt, then: python3 $HARNESS/grade-run.py $BASE"
