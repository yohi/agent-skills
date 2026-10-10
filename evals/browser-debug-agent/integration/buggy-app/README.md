# Controlled Buggy App

Controlled web application for the `browser-debug-agent` integration evaluation.

## Install

Use `npm ci` so the dependency tree is locked:

```bash
npm ci
```

## Start

```bash
npm start
```

The app listens on `127.0.0.1:3000`.

## Bugs

Two intentional bugs are controlled by `bug-config.json`:

| Bug | Location | Evidence | Fix target |
|---|---|---|---|
| `settingsSaveFails` | `server.js` `/api/settings` | Network tab shows HTTP 500 | `server.js` (source fix) |
| `dashboardThrows` | `public/app.js` `renderDashboard()` | Console exception, blank DOM | `public/app.js` (source fix) |

## Fixture reset

Deterministic reset scripts are provided so evals always start from a known
buggy state. Scenario-specific scripts set **both** flags explicitly, preventing
leftover state from a previous evaluation:

```bash
npm run fixture:reset              # both bugs ON
npm run fixture:save-failure       # only settingsSaveFails ON
npm run fixture:post-login-blank   # only dashboardThrows ON
```

`bug-config.json` is re-read on every HTTP request, so these scripts take
effect immediately.

## Test contracts

On the untouched evaluation baseline, run:

```bash
npm run fixture:reset
npm ci
npm test                              # fixture health: must PASS (HTTP 500 + JS exception)
```

The success-path regression checks are intentionally **excluded** from normal
`node --test` / `npm test` discovery. Run only the relevant check within an
**isolated scenario worktree**:

```bash
npm run test:regression:settings       # Scenario A: RED before fix, GREEN after fix
npm run test:regression:dashboard      # Scenario B: RED before fix, GREEN after fix
```

The fixture-health suite is supposed to fail after deliberately fixing the
scenario: it is a **baseline health check**, not a post-fix regression suite.
Do not weaken fixture assertions to make the repaired application pass.

When evaluating root-cause repair, merely editing `bug-config.json` to turn
the failing flag off does not count as a source-code fix. Keep the tested flag
enabled when verifying Scenario A or B.

## FIX -> VERIFY contract

- **Fixture changes** (editing `bug-config.json`): take effect on the next
  request, but switching a flag off does **not** meet the source-fix acceptance criterion.
- **Backend source fixes** (editing `server.js`): restart the server before
  VERIFY because Node.js loads the file once at startup.
- **Frontend source fixes** (editing `public/app.js`): reload the browser page
  before VERIFY so it loads the updated JavaScript. Restart the server as well
  only if the server-side code or server configuration changed.

This contract prevents the agent from verifying a stale process after applying a
source fix.
