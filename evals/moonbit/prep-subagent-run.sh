#!/bin/bash
# prep-subagent-run.sh <run-id> [trials=3] [scratch=/tmp/moonbit-skill-evals] [tasks=<comma-list>]
#
# Prepares sandboxes + per-trial prompt files for the SUBAGENT mode (see
# README "Subagent mode"). The orchestrating Claude session then spawns one
# subagent per prompt file (model: sonnet) and finally runs grade-run.py.
#
# Each task's meta.json may name the skill it tests ("skill", default
# moonbit); the skill variant ships that skill's files at ./<skill>-docs/.
set -euo pipefail
RUN_ID="${1:?usage: prep-subagent-run.sh <run-id> [trials] [scratch] [tasks]}"
TRIALS="${2:-3}"
SCRATCH="${3:-/tmp/moonbit-skill-evals}"
ONLY_TASKS="${4:-}"
HARNESS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HARNESS/../.." && pwd)"
BASE="$SCRATCH/$RUN_ID"

rm -rf "$BASE" && mkdir -p "$BASE"

CONTROL_RULES="RULES: Work ONLY inside that directory — never read, search, or write any file outside it. Do NOT use the Skill tool and do not load any skills. Rely only on your own knowledge and the files inside the project."
FINAL='FINAL MESSAGE: reply with exactly one JSON object, no other text: {"done": <bool>, "consulted_docs": <bool>, "moon_failures_seen": <int, number of times a moon check/test/build run reported errors or test failures during your work>, "notes": "<max 200 chars>"}'

for task_dir in "$HARNESS"/tasks/*/; do
  task="$(basename "$task_dir")"
  if [ -n "$ONLY_TASKS" ]; then
    case ",$ONLY_TASKS," in
      *",$task,"*) ;;
      *) continue ;;
    esac
  fi
  skill="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('skill','moonbit'))" "$task_dir/meta.json" 2>/dev/null || echo moonbit)"
  skill_src="$REPO/$skill"
  [ -f "$skill_src/SKILL.md" ] || { echo "skill '$skill' for task $task not found at $skill_src" >&2; exit 1; }
  skill_rules="RULES: Work ONLY inside that directory — never read, search, or write any file outside it. Do NOT use the Skill tool and do not load any skills. The project ships reference documentation at ./$skill-docs/ (SKILL.md plus references/): read ./$skill-docs/SKILL.md first and consult the relevant reference files before writing any code."
  for variant in control skill; do
    for ((i = 0; i < TRIALS; i++)); do
      name="$task--sub--$variant--$(printf '%02d' "$i")"
      d="$BASE/$name"
      mkdir -p "$d"
      cp -R "$task_dir/template" "$d/work"
      rules="$CONTROL_RULES"
      if [ "$variant" = "skill" ]; then
        mkdir -p "$d/work/$skill-docs"
        cp -R "$skill_src/SKILL.md" "$skill_src/references" "$d/work/$skill-docs/"
        rules="$skill_rules"
      fi
      {
        echo "Complete a coding task in the directory $d/work (cd there first; all paths below are relative to it)."
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
