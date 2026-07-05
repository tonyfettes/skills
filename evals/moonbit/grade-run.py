#!/usr/bin/env python3
"""grade-run.py <run-base-dir> [--agent-label claude-sub]

Grades every sandbox under <run-base-dir> (created by prep-subagent-run.sh,
trial dirs named <task>--sub--<variant>--<nn>) by running each task's
verify.sh, writes results/<run-id>/results.jsonl, and prints the report.

Use after the orchestrating session's subagents have finished. Idempotent —
verify.sh re-injects conformance packages on every run.
"""

import json
import subprocess
import sys
from pathlib import Path

HARNESS = Path(__file__).resolve().parent


def main():
    base = Path(sys.argv[1]).resolve()
    label = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "--agent-label" else "claude-sub"
    run_id = base.name
    out_dir = HARNESS / "results" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)
    results_path = out_dir / "results.jsonl"

    rows = []
    for trial in sorted(base.iterdir()):
        if not (trial / "work").is_dir():
            continue
        task, _, variant, idx = trial.name.split("--")
        verify = HARNESS / "tasks" / task / "verify.sh"
        v = subprocess.run(["bash", str(verify), str(trial / "work")],
                           capture_output=True, text=True)
        passed = v.returncode == 0
        (trial / "verify.log").write_text(v.stdout + v.stderr)

        row = {
            "run_id": run_id, "task": task, "agent": label,
            "variant": variant, "trial": int(idx),
            "pass": passed, "status": "ok", "duration_s": 0,
            "verify_tail": (v.stdout + v.stderr).strip().splitlines()[-1:],
        }
        # self-report left by the orchestrator, if any (report.json per trial)
        sr = trial / "report.json"
        if sr.exists():
            try:
                row["self_report"] = json.loads(sr.read_text())
            except Exception:
                pass
        rows.append(row)
        print(f"[{'PASS' if passed else 'FAIL'}] {trial.name}")

    with open(results_path, "w") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"\n{len(rows)} rows -> {results_path}\n")
    subprocess.run([sys.executable, str(HARNESS / "report.py"), str(results_path)])


if __name__ == "__main__":
    main()
