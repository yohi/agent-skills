# Integration Evaluation

## Purpose

This directory contains the integration evaluation scenarios for the
browser-debug-agent Skill. Scenarios A and B require a real Chrome browser
connected via the official Chrome DevTools MCP. Scenario C is an exception: it
tests PRECHECK failure when the SSH tunnel is down and does not require a Chrome
connection.

## Important policy

- **Do not run Scenarios A or B** unless a real Chrome instance is reachable at
  `http://127.0.0.1:9222` through the SSH tunnel. Scenario C intentionally runs
  with the tunnel down.
- A failure to connect must be reported as `NOT_VERIFIED` or `BLOCKED`. Never
  fabricate `FIX_VERIFIED` or `VERIFIED`.

## Scenarios

### A. `save-failure`

- URL: `http://127.0.0.1:3000/settings.html`
- Bug: `POST /api/settings` returns HTTP 500.
- Primary evidence: **Network** tab.
- Expected fix: minimal backend change so `/api/settings` returns 200.

### B. `post-login-blank`

- URL: `http://127.0.0.1:3000/login.html`
- Bug: after login, dashboard throws a JavaScript exception and renders blank.
- Primary evidence: **Console** + **DOM** + **Screenshot**.
- Expected fix: minimal frontend change so dashboard renders correctly.

### C. `cdp-unavailable-fail-closed`

- Condition: the SSH tunnel to Chrome is intentionally down.
- Expected behavior: PRECHECK fails, report `NOT_VERIFIED`/`BLOCKED`.
- No source-code changes, no `FIX_VERIFIED`.

## Files

- `integration-evals.json` — prompts and expected outcomes for each scenario.

## How to run

1. Start Chrome on the Browser Host.
2. Start the SSH tunnel from the Browser Host.
3. Start the buggy app on the Agent Host.
4. Configure Chrome DevTools MCP on the Agent Host.
5. Give one of the prompts in `integration-evals.json` to an AI agent that has
   loaded the browser-debug-agent Skill.
6. Grade the result against the expectations in `integration-evals.json`.

## FIX_VERIFIED rule

`FIX_VERIFIED` may only be reported when **all** of the following are true:

1. A source fix was applied.
2. The same browser scenario was re-executed.
3. The expected UI/result was observed.
4. The relevant browser failure is absent (no 500, no Console exception,
   no empty DOM).

## Reproducible starting state

The checked-in app is intentionally broken. Before Scenario A/B, create a
disposable worktree and run `npm ci && npm run fixture:reset && npm test`
inside its `buggy-app` directory. The health suite must PASS because it
observes the expected failure behaviors, not a repaired application.

Use `npm run fixture:save-failure` or `npm run fixture:post-login-blank`
to isolate a single active bug. Fix the source without disabling the active
bug flag. The separately invoked `npm run test:regression:settings` or
`npm run test:regression:dashboard` should be RED before the fix and GREEN
afterward, but browser verification is still mandatory.

Keep each scenario on an independent branch/worktree. Do not merge source
fixes or captured evaluation outputs into the fixture baseline.
