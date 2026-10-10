#!/usr/bin/env python3
"""Aggregate grading and timing into benchmark.json."""

import argparse
import json
import statistics
from datetime import datetime, timezone
from pathlib import Path


def load_grading(eval_dir: Path, config: str) -> dict:
    path = eval_dir / config / "grading.json"
    return json.loads(path.read_text(encoding="utf-8"))


def load_timing(eval_dir: Path, config: str) -> dict:
    path = eval_dir / config / "timing.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    return data


def load_metadata(eval_dir: Path) -> dict:
    path = eval_dir / "eval_metadata.json"
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iteration", default="iteration-1")
    args = parser.parse_args()

    workspace = Path(__file__).parent / args.iteration

    eval_map = {
        "eval-reproduce-and-fix": 1,
        "eval-verify-behavior": 2,
        "eval-debug-no-fix": 3,
        "eval-adversarial-no-browser-fix": 4,
        "eval-fix-authorized-no-browser": 5,
    }

    runs = []
    per_config = {"with_skill": [], "without_skill": []}

    for eval_dir in sorted(workspace.iterdir()):
        if not eval_dir.is_dir() or eval_dir.name not in eval_map:
            continue
        meta = load_metadata(eval_dir)
        for config in ("with_skill", "without_skill"):
            grading = load_grading(eval_dir, config)
            timing = load_timing(eval_dir, config)
            duration = timing.get("total_duration_seconds") or (timing.get("duration_ms", 0) / 1000)
            passed = grading["summary"]["passed"]
            total = grading["summary"]["total"]
            run = {
                "eval_id": meta["eval_id"],
                "eval_name": meta["eval_name"],
                "configuration": config,
                "run_number": 1,
                "result": {
                    "pass_rate": passed / total if total else 0.0,
                    "passed": passed,
                    "failed": total - passed,
                    "total": total,
                    "time_seconds": duration,
                    "tokens": timing.get("total_tokens") or 0,
                    "tool_calls": None,
                    "errors": None,
                },
                "expectations": grading["expectations"],
                "notes": [],
            }
            runs.append(run)
            per_config[config].append(run["result"])

    def summarize(results):
        pass_rates = [r["pass_rate"] for r in results]
        times = [r["time_seconds"] for r in results]
        tokens = [r["tokens"] for r in results]
        return {
            "pass_rate": {
                "mean": statistics.mean(pass_rates) if pass_rates else 0.0,
                "stddev": statistics.stdev(pass_rates) if len(pass_rates) > 1 else 0.0,
                "min": min(pass_rates) if pass_rates else 0.0,
                "max": max(pass_rates) if pass_rates else 0.0,
            },
            "time_seconds": {
                "mean": statistics.mean(times) if times else 0.0,
                "stddev": statistics.stdev(times) if len(times) > 1 else 0.0,
                "min": min(times) if times else 0.0,
                "max": max(times) if times else 0.0,
            },
            "tokens": {
                "mean": statistics.mean(tokens) if tokens else 0.0,
                "stddev": statistics.stdev(tokens) if len(tokens) > 1 else 0.0,
                "min": min(tokens) if tokens else 0.0,
                "max": max(tokens) if tokens else 0.0,
            },
        }

    with_skill_summary = summarize(per_config["with_skill"])
    without_skill_summary = summarize(per_config["without_skill"])

    delta = {
        "pass_rate": f"{with_skill_summary['pass_rate']['mean'] - without_skill_summary['pass_rate']['mean']:+.2f}",
        "time_seconds": f"{with_skill_summary['time_seconds']['mean'] - without_skill_summary['time_seconds']['mean']:+.2f}",
        "tokens": f"{with_skill_summary['tokens']['mean'] - without_skill_summary['tokens']['mean']:+.0f}",
    }

    benchmark = {
        "metadata": {
            "skill_name": "browser-debug-agent",
            "skill_path": "skills/browser-debug-agent",
            "executor_model": "kimi-k2.7-code",
            "analyzer_model": "kimi-k2.7-code",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "evals_run": sorted(eval_map.values()),
            "runs_per_configuration": 1,
        },
        "runs": runs,
        "run_summary": {
            "with_skill": with_skill_summary,
            "without_skill": without_skill_summary,
            "delta": delta,
        },
        "notes": [
            "All runs encountered an unavailable browser MCP / unreachable target app, as expected for this fail-closed evaluation round.",
            "Token counts were not available from the executor notifications and are recorded as 0.",
            "With-skill runs completed faster on average than baseline runs despite producing equivalent fail-closed reports.",
            "Assertions focus on fail-closed behavior and workflow-contract compliance; they do not yet exercise real browser interactions.",
        ],
    }

    benchmark_path = workspace / "benchmark.json"
    benchmark_path.write_text(json.dumps(benchmark, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {benchmark_path}")
    print(f"With-skill pass rate: {with_skill_summary['pass_rate']['mean']:.2%}")
    print(f"Without-skill pass rate: {without_skill_summary['pass_rate']['mean']:.2%}")


if __name__ == "__main__":
    main()
