# Browser Debug Agent Evaluation Assets

This directory contains evaluation fixtures and definitions for the
`browser-debug-agent` Skill. It is not required to install or use the Skill at
runtime.

## Contents

- `integration/` — controlled buggy app, Browser Host and SSH tunnel setup,
  Chrome DevTools MCP instructions, and real-browser evaluation scenarios.
- `evals/evals.json` — offline evaluation prompts and expected outcomes.

## Real Chrome integration evaluation

Follow [`integration/README.md`](integration/README.md) for Browser Host,
Agent Host, Chrome, SSH tunnel, and Chrome DevTools MCP setup. The controlled
app and scripts use paths relative to their own files, so the internal
`integration/` layout should be preserved.

Evaluation definitions are retained; per-run reports, scores, timing data, and
benchmarks are not stored in this repository.

## Re-running integration scenarios

Keep the intentional bugs in `integration/buggy-app`. The fixture-health
tests are part of the versioned evaluation definition:

```bash
cd evals/browser-debug-agent/integration/buggy-app
npm ci
npm run fixture:reset
npm test
```

Perform actual bug fixes in fresh, isolated worktrees. The
`test:regression:settings` / `test:regression:dashboard` scripts are
**post-fix** checks and are not included in the baseline fixture-health run.
Real-browser evidence remains required to claim `FIX_VERIFIED`.
