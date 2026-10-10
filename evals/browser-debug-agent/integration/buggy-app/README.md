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
| `settingsSaveFails` | `server.js` `/api/settings` | Network tab shows HTTP 500 | `server.js` or `bug-config.json` |
| `dashboardThrows` | `public/app.js` `renderDashboard()` | Console exception, blank DOM | `public/app.js` or `bug-config.json` |

## Fixture reset

Deterministic reset scripts are provided so evals always start from a known
buggy state:

```bash
npm run fixture:reset              # both bugs ON
npm run fixture:save-failure       # only settingsSaveFails ON
npm run fixture:post-login-blank   # only dashboardThrows ON
```

`bug-config.json` is re-read on every HTTP request, so these scripts take
effect immediately.

## FIX -> VERIFY contract

- **Config-only fixes** (editing `bug-config.json`): take effect on the next
  request; no server restart needed.
- **Source-code fixes** (editing `server.js` or `public/app.js`): the agent
  **must restart** the server before VERIFY, because Node.js loads those files
  once at startup.

This contract prevents the agent from verifying a stale process after applying a
source fix.
