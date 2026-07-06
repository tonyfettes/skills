#!/usr/bin/env python3
"""Aggregate results.jsonl into a pass-rate table with Wilson intervals."""

import json
import math
import sys
from collections import defaultdict


def wilson(passed, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = passed / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    m = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, c - m), min(1.0, c + m))


def main(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    groups = defaultdict(list)
    for r in rows:
        groups[(r["task"], r["agent"], r["variant"])].append(r)

    hdr = f"{'task':<28} {'agent':<7} {'variant':<8} {'pass':>9} {'95% CI':>14} {'skill_ld':>8} {'err_rnds':>8} {'avg_s':>7}"
    print(hdr)
    print("-" * len(hdr))
    for key in sorted(groups):
        g = groups[key]
        n = len(g)
        p = sum(1 for r in g if r["pass"])
        lo, hi = wilson(p, n)
        loaded = sum(1 for r in g if r.get("skill_loaded"))
        err = sum(r.get("compile_errors_seen",
                        (r.get("self_report") or {}).get("moon_failures_seen", 0))
                  for r in g) / n
        dur = sum(r.get("duration_s", 0) for r in g) / n
        print(f"{key[0]:<28} {key[1]:<7} {key[2]:<8} {p:>4}/{n:<4} "
              f"[{lo:.2f},{hi:.2f}] {loaded:>5}/{n:<2} {err:>8.1f} {dur:>7.0f}")

    # paired per-task delta (skill - control), per agent
    print("\nΔ pass rate (skill - control):")
    tasks = sorted({r["task"] for r in rows})
    agents = sorted({r["agent"] for r in rows})
    for a in agents:
        for t in tasks:
            c = groups.get((t, a, "control"), [])
            s = groups.get((t, a, "skill"), [])
            if not c or not s:
                continue
            pc = sum(r["pass"] for r in c) / len(c)
            ps = sum(r["pass"] for r in s) / len(s)
            print(f"  {a:<7} {t:<28} {pc:.2f} -> {ps:.2f}  ({ps - pc:+.2f})")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "results.jsonl")
