# Browser Debug Agent Evaluation Assets

This directory contains evaluation fixtures and evidence for the
`browser-debug-agent` Skill. It is not required to install or use the Skill at
runtime.

## Contents

- `integration/` — controlled buggy app, Browser Host and SSH tunnel setup,
  Chrome DevTools MCP instructions, real-browser evaluation scenarios, reports,
  and captured evidence.
- `iteration-1/` through `iteration-4/` — historical offline evaluation runs,
  grading outputs, timing data, benchmark summaries, and review pages. These
  are retained as evaluation records; historical outputs and scenario reports
  preserve path strings from the former `browser-debug-agent-workspace/`
  location where those paths identify the original run or commit.
- `evals/evals.json` — offline evaluation prompts and expectations.
- `grade_iteration.py` — grades an iteration's recorded outputs.
- `aggregate_benchmark.py` — aggregates an iteration's grading and timing data.

## Real Chrome integration evaluation

Follow [`integration/README.md`](integration/README.md) for Browser Host,
Agent Host, Chrome, SSH tunnel, and Chrome DevTools MCP setup. The controlled
app and scripts use paths relative to their own files, so the internal
`integration/` layout should be preserved.

## Offline evaluation tools

Run these from the repository root:

```bash
python3 evals/browser-debug-agent/grade_iteration.py --iteration iteration-4
python3 evals/browser-debug-agent/aggregate_benchmark.py --iteration iteration-4
```

These commands rewrite `grading.json` and `benchmark.json` in the selected
iteration. Use them only when regenerating those evaluation outputs is
intended.
