#!/usr/bin/env python3
"""A/B eval runner for the moonbit skill.

One trial = (task, agent, variant). The task template is copied into a
throwaway sandbox outside the repo, the agent CLI runs headless inside it
(with the skill injected or not, per variant), then the task's verify.sh
grades the result with hidden conformance tests.

Isolation:
  - claude: fresh CLAUDE_CONFIG_DIR per trial (no global ~/.claude skills).
            Auth: export ANTHROPIC_API_KEY, or pass --claude-config-seed DIR
            whose contents are copied into the fresh config dir.
  - codex:  fresh CODEX_HOME per trial with only auth.json copied in.
Skill injection (variant != control):
  - claude: <work>/.claude/skills/moonbit
  - codex:  <CODEX_HOME>/skills/moonbit
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HARNESS = Path(__file__).resolve().parent
TASKS_DIR = HARNESS / "tasks"
SKILL_SRC = HARNESS.parent.parent / "moonbit"
RESULTS_DIR = HARNESS / "results"

_write_lock = threading.Lock()


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def tool_version(cmd):
    try:
        return sh(cmd).stdout.strip().splitlines()[0]
    except Exception as e:
        return f"unavailable: {e}"


def build_prompt(task_dir):
    return (task_dir / "prompt.md").read_text()


def isolated_env(trial_dir):
    """Copy of os.environ with HOME pointed at an empty dir — otherwise both
    CLIs discover the globally installed skill via ~/.agents/skills and the
    control group is contaminated (verified empirically for codex)."""
    fake_home = trial_dir / "home"
    fake_home.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["HOME"] = str(fake_home)
    real_moon = Path.home() / ".moon"
    if real_moon.exists() and "MOON_HOME" not in env:
        env["MOON_HOME"] = str(real_moon)
    return env


def setup_claude(trial_dir, work, variant, args):
    home = trial_dir / "claude-home"
    home.mkdir(parents=True)
    if args.claude_config_seed:
        shutil.copytree(args.claude_config_seed, home, dirs_exist_ok=True)
    if variant != "control":
        shutil.copytree(SKILL_SRC, work / ".claude" / "skills" / "moonbit")
    env = isolated_env(trial_dir)
    env["CLAUDE_CONFIG_DIR"] = str(home)
    cmd = [
        "claude", "-p", build_prompt(trial_dir / "task"),
        "--output-format", "stream-json", "--verbose",
        "--max-turns", str(args.max_turns),
        "--dangerously-skip-permissions",
        "--model", args.claude_model,
    ]
    return cmd, env


def setup_codex(trial_dir, work, variant, args):
    home = trial_dir / "codex-home"
    home.mkdir(parents=True)
    auth = Path.home() / ".codex" / "auth.json"
    if auth.exists():
        shutil.copy(auth, home / "auth.json")
    if variant != "control":
        shutil.copytree(SKILL_SRC, home / "skills" / "moonbit")
    env = isolated_env(trial_dir)
    env["CODEX_HOME"] = str(home)
    cmd = [
        "codex", "exec", "--json",
        "--skip-git-repo-check",
        "--sandbox", "workspace-write",
        "-o", str(trial_dir / "last_message.txt"),
    ]
    if args.codex_model:
        cmd += ["-m", args.codex_model]
    cmd.append(build_prompt(trial_dir / "task"))
    return cmd, env


def transcript_metrics(text):
    return {
        # any read/mention of the injected skill files (paths only — a bare
        # "references/" also appears in vendored dep paths and false-fires)
        "skill_loaded": bool(re.search(r"skills/moonbit|moonbit-docs|SKILL\.md", text)),
        # compiler diagnostic rounds observed in tool output
        "compile_errors_seen": len(re.findall(r"Error: \[", text)),
        "deprecation_warnings_seen": len(re.findall(r"Warning: \[0020\]|Warning: \[0027\]", text)),
        "moon_invocations": len(re.findall(r"\bmoon (?:check|test|build|run|add|info)", text)),
    }


def claude_result_metrics(transcript_path):
    """Pull cost/turns from the final result event of stream-json output."""
    out = {}
    try:
        for line in transcript_path.read_text().splitlines():
            if '"type":"result"' in line or '"type": "result"' in line:
                d = json.loads(line)
                out = {
                    "cost_usd": d.get("total_cost_usd"),
                    "turns": d.get("num_turns"),
                    "agent_reported_error": d.get("is_error"),
                }
    except Exception:
        pass
    return out


def run_trial(spec, args, run_dir):
    task, agent, variant, idx = spec
    name = f"{task}--{agent}--{variant}--{idx:02d}"
    trial_dir = Path(args.scratch) / args.run_id / name
    if trial_dir.exists():
        shutil.rmtree(trial_dir)
    trial_dir.mkdir(parents=True)

    task_src = TASKS_DIR / task
    # symlink task dir for prompt access, copy template as the workdir
    (trial_dir / "task").symlink_to(task_src)
    work = trial_dir / "work"
    shutil.copytree(task_src / "template", work)

    if agent == "claude":
        cmd, env = setup_claude(trial_dir, work, variant, args)
    elif agent == "codex":
        cmd, env = setup_codex(trial_dir, work, variant, args)
    else:
        raise ValueError(agent)

    transcript = trial_dir / "transcript.jsonl"
    t0 = time.time()
    status = "ok"
    try:
        with open(transcript, "w") as f:
            p = subprocess.run(cmd, cwd=work, env=env, stdout=f,
                               stderr=subprocess.STDOUT, timeout=args.timeout)
        agent_rc = p.returncode
    except subprocess.TimeoutExpired:
        status, agent_rc = "agent_timeout", -1
    duration = round(time.time() - t0, 1)

    v = sh(["bash", str(task_src / "verify.sh"), str(work)])
    passed = v.returncode == 0
    (trial_dir / "verify.log").write_text(v.stdout + v.stderr)

    text = transcript.read_text() if transcript.exists() else ""
    row = {
        "run_id": args.run_id, "task": task, "agent": agent,
        "variant": variant, "trial": idx,
        "pass": passed, "status": status, "agent_rc": agent_rc,
        "duration_s": duration,
        "verify_tail": (v.stdout + v.stderr).strip().splitlines()[-1:],
        **transcript_metrics(text),
    }
    if agent == "claude":
        row.update(claude_result_metrics(transcript))

    with _write_lock:
        with open(run_dir / "results.jsonl", "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    tag = "PASS" if passed else "FAIL"
    print(f"[{tag}] {name} ({duration}s)", flush=True)

    if not args.keep and passed:
        shutil.rmtree(trial_dir, ignore_errors=True)
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--tasks", default=",".join(sorted(p.name for p in TASKS_DIR.iterdir() if p.is_dir())))
    ap.add_argument("--agents", default="claude")
    ap.add_argument("--variants", default="control,skill")
    ap.add_argument("--trials", type=int, default=3)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--timeout", type=int, default=1200, help="seconds per agent run")
    ap.add_argument("--max-turns", type=int, default=50)
    ap.add_argument("--claude-model", default="claude-sonnet-5")
    ap.add_argument("--codex-model", default=None)
    ap.add_argument("--claude-config-seed", default=None,
                    help="dir copied into each trial's fresh CLAUDE_CONFIG_DIR (for auth)")
    ap.add_argument("--scratch", default="/tmp/moonbit-skill-evals")
    ap.add_argument("--keep", action="store_true", help="keep sandboxes of passing trials too")
    args = ap.parse_args()

    run_dir = RESULTS_DIR / args.run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    skill_rev = sh(["git", "-C", str(SKILL_SRC), "rev-parse", "--short", "HEAD"]).stdout.strip()
    dirty = bool(sh(["git", "-C", str(SKILL_SRC), "status", "--porcelain", "--", "moonbit"]).stdout.strip())
    manifest = {
        "run_id": args.run_id,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "moon": tool_version(["moon", "version"]),
        "claude": tool_version(["claude", "--version"]),
        "codex": tool_version(["codex", "--version"]),
        "skill_rev": skill_rev + ("+dirty" if dirty else ""),
        "args": {k: v for k, v in vars(args).items()},
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

    specs = [
        (t, a, v, i)
        for t in args.tasks.split(",")
        for a in args.agents.split(",")
        for v in args.variants.split(",")
        for i in range(args.trials)
    ]
    print(f"{len(specs)} trials -> {run_dir}", flush=True)
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(run_trial, s, args, run_dir) for s in specs]
        for f in as_completed(futs):
            f.result()

    subprocess.run([sys.executable, str(HARNESS / "report.py"), str(run_dir / "results.jsonl")])


if __name__ == "__main__":
    main()
