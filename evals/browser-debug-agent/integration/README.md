# browser-debug-agent Integration Setup

This directory contains everything needed to run the **integration evaluation**
for the `browser-debug-agent` Skill with a real Chrome browser.

## Architecture

```text
Ubuntu Desktop / Browser Host
┌──────────────────────────────────────┐
│ Google Chrome (headful)              │
│   --remote-debugging-port=9222       │
│   --user-data-dir=.../chrome-profile  │
│                                      │
│ Chrome sees app as:                  │
│   http://127.0.0.1:3000              │
└───────┬───────────────────▲──────────┘
        │                   │
        │ SSH -R            │ SSH -L
        │ CDP               │ Web App
        ▼                   │
┌──────────────────────────────────────┐
│ Ubuntu Server / AI Agent Host          │
│                                      │
│ Chrome DevTools MCP                  │
│   --browser-url=http://127.0.0.1:9222│
│                                      │
│ browser-debug-agent Skill          │
│                                      │
│ Controlled buggy app               │
│   http://127.0.0.1:3000              │
│                                      │
│ Source repository                    │
└──────────────────────────────────────┘
```

A single SSH connection carries both tunnels:

```bash
ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -R 127.0.0.1:9222:127.0.0.1:9222 \
  -L 127.0.0.1:3000:127.0.0.1:3000 \
  ai-agent
```

All endpoints bind to **loopback only**. CDP and the web app are not exposed to
LAN or Tailscale directly.

## What is included

| Directory | Purpose |
|---|---|
| `buggy-app/` | Controlled web app with two intentional bugs |
| `browser-host/` | Chrome launch script for the Browser Host |
| `ssh-tunnel/` | SSH tunnel script for the Browser Host |
| `mcp/` | Chrome DevTools MCP connection notes |
| `eval/` | Integration eval prompts and expectations |

## What is NOT included

- A custom MCP wrapper.
- A Browser Host management plugin.
- Playwright MCP (v1 uses Chrome DevTools MCP only).
- Automatic Chrome installation.

## Startup order

1. **Agent Host**: start the controlled buggy app.
2. **Browser Host**: start Google Chrome with remote debugging.
3. **Browser Host**: start the SSH tunnel to the Agent Host.
4. **Agent Host**: run the PRECHECK.
5. **Agent Host**: configure/start the Chrome DevTools MCP.
6. **Agent Host**: run an integration eval prompt.

## Step-by-step instructions

### 1. Start the buggy app (Agent Host)

Use `npm ci` so the dependency tree is locked:

```bash
cd evals/browser-debug-agent/integration/buggy-app
npm ci
npm start
```

The app listens on `127.0.0.1:3000`.

To verify:

```bash
curl -s http://127.0.0.1:3000/api/config
```

### 2. Start Chrome (Browser Host)

Run this inside an active Ubuntu Desktop graphical session (X11/Wayland), not
from a plain SSH shell:

```bash
cd evals/browser-debug-agent/integration/browser-host
./start-chrome.sh
```

Chrome will fail to start if it is not installed. The script will not install it
for you. Headful Chrome is required because some UI bugs only reproduce in a
real browser window.

To verify CDP is listening:

```bash
curl -s http://127.0.0.1:9222/json/version
```

### 3. Start the SSH tunnel (Browser Host)

Set environment variables if needed, then:

```bash
cd evals/browser-debug-agent/integration/ssh-tunnel
export AGENT_HOST="ai-agent"
export AGENT_SSH_USER="agent-user"
export SSH_KEY="$HOME/.ssh/id_ed25519"
./setup-tunnel.sh
```

The tunnel is fail-closed (`ExitOnForwardFailure=yes`). If either port forward
cannot be created, the SSH process exits immediately. Leave this running. Press
`Ctrl-C` to tear down.

### 4. PRECHECK (Agent Host)

Before any integration eval, the agent must confirm **all** of the following:

1. CDP is reachable:
   ```bash
   curl -s http://127.0.0.1:9222/json/version
   ```
   Expected: JSON with `Browser` / `Protocol-Version`.
2. Browser product/version is what the eval expects (e.g. Google Chrome).
3. The target app is reachable:
   ```bash
   curl -s http://127.0.0.1:3000/api/config
   ```
4. The expected bug configuration is confirmed (e.g. `settingsSaveFails: true`
   for Scenario A).
5. Chrome DevTools MCP is connected and at least one tool call succeeds.

If any check fails, the agent must report `NOT_VERIFIED` or `BLOCKED`.

### 5. Configure Chrome DevTools MCP (Agent Host)

Use the official package directly, pinned to the verified version:

```bash
npx chrome-devtools-mcp@1.10.1 --browser-url=http://127.0.0.1:9222
```

Configure this command in your MCP client (Claude Code, OpenCode, etc.). Do not
use a wrapper. Update the version pin only after re-verifying the integration.

### 6. Run an integration eval (Agent Host)

Use one of the prompts in `eval/integration-evals.json`.

## FIX -> VERIFY contract

The app has two kinds of changes with different activation rules:

- **Fixture changes** (editing `buggy-app/bug-config.json`): take effect on
  the next request, but disabling the bug does **not** qualify as a source fix.
- **Backend source fixes** (`buggy-app/server.js`): restart the server before VERIFY.
- **Frontend source fixes** (`buggy-app/public/app.js`): reload the page to
  fetch updated JavaScript; restart the server only for backend changes.

This contract prevents the agent from verifying a stale process after applying a
source fix.

## Deterministic fixture reset

After an eval fixes a bug, restore the known buggy state before the next run:

```bash
cd evals/browser-debug-agent/integration/buggy-app
npm run fixture:reset              # both bugs ON
npm run fixture:save-failure       # only settingsSaveFails ON
npm run fixture:post-login-blank   # only dashboardThrows ON
```

`bug-config.json` is re-read on every request, so these scripts take effect
immediately. The scenario-specific scripts set the other flag to `false`.
Run `npm test` after `fixture:reset` to confirm the intended HTTP 500 and
Dashboard exception remain reproducible. Restore a clean worktree before each
new evaluation; resetting config alone cannot undo an applied source fix.

## Teardown

1. Stop the integration eval/agent.
2. Stop the Chrome DevTools MCP.
3. Stop the SSH tunnel (`Ctrl-C` in its terminal).
4. Stop Google Chrome on the Browser Host.
5. Stop the buggy app on the Agent Host.

## Bug ON/OFF

The bugs are controlled by `buggy-app/bug-config.json`:

```json
{
  "settingsSaveFails": true,
  "dashboardThrows": true
}
```

Use the `fixture:*` scripts above to set this deterministically.

## Integration eval scenarios

See `eval/README.md` and `eval/integration-evals.json` for the three required
scenarios:

- **A. save-failure**: Network 500 on save.
- **B. post-login-blank**: JavaScript exception after login.
- **C. cdp-unavailable**: fail-closed behavior when the tunnel is down.

## Minimum human-side work

Before the AI agent can run integration evals, a human must:

1. Install Google Chrome on the Ubuntu Desktop / Browser Host.
2. Ensure the Browser Host can SSH to the Agent Host.
3. Start Chrome on the Browser Host using `browser-host/start-chrome.sh` from an
   active graphical session.
4. Start the SSH tunnel on the Browser Host using `ssh-tunnel/setup-tunnel.sh`.
5. Install Node.js dependencies with `npm ci` and start the buggy app on the
   Agent Host.
6. Configure the Chrome DevTools MCP command in the MCP client on the Agent
   Host.

After that, the AI agent can run the integration evals autonomously, except
for Scenario C's tunnel shutdown if the agent cannot safely identify the
isolated tunnel process. Never terminate unrelated SSH sessions.

## Evaluation result retention

The scenario definitions and expected outcomes are maintained in
[`eval/README.md`](eval/README.md) and [`eval/integration-evals.json`](eval/integration-evals.json).
Per-run reports and screenshots are not retained in this repository.

## Isolation and reproducibility

The committed `buggy-app` is an **intentionally broken, reusable baseline**.
Never merge Scenario A/B source fixes into it.

For each run, create a fresh `git worktree` or disposable clone from the
evaluation baseline. Reset the selected fixture, verify its expected failure,
and run the browser evaluation there. For example, from the repository root:

```bash
git worktree add -b eval/browser-debug-a-<run-id> /tmp/browser-debug-a-<run-id> HEAD
cd /tmp/browser-debug-a-<run-id>/evals/browser-debug-agent/integration/buggy-app
npm ci
npm run fixture:reset
npm test
npm run fixture:save-failure
# Start this worktree's app and perform Scenario A against it.
# Before source fixes: npm run test:regression:settings must fail (RED).
# After a permitted fix: it must pass (GREEN), followed by the real-browser VERIFY.
```

Use a unique branch, directory, and (if concurrent) server port per run. Do not
run multiple scenarios against the same app process or browser session.
`fixture:reset` changes **only** `bug-config.json`; it does not restore
modified source files. Preserve run-specific reports/screenshots outside this
repository, or in ignored `eval/runs/` and `eval/evidence/` paths.
