# Integration Report — Scenario C: tunnel fail-closed

## Run metadata

- Baseline: `d75d376d17c8558b90f18f1d037fd548455853b3`
- Scenario branch: `scenario-c-tunnel-fail-closed`
- Intended condition: stop only the Browser Host evaluation SSH tunnel that exposes CDP to the Agent Host
- Browser MCP: `chrome-devtools-mcp@1.10.1`
- Browser: Google Chrome 155 (previously observed Chrome user agent)
- Result: `NOT_VERIFIED`

## Branch isolation

- Scenario C was created at baseline `d75d376d17c8558b90f18f1d037fd548455853b3` after Scenario B commit `038cc294e085b725c516c1154ce91801572621b0` succeeded and its worktree was clean.
- Neither Scenario A commit `5d69e89083c05ff1560e095b16090a56d200d5fe` nor Scenario B commit `038cc294e085b725c516c1154ce91801572621b0` is an ancestor of this branch.
- C branch HEAD remained at the baseline during this evaluation.

## PRECHECK — before attempted cutover

| Check | Evidence |
|---|---|
| Chrome DevTools MCP | `list_pages` succeeded and returned three pages, including the selected Dashboard page. |
| Target app | Chrome runtime `fetch('/api/config')` returned status 200 with `{"settingsSaveFails":true,"dashboardThrows":true}`; `fetch('/login.html')` returned 200. |
| Current page | URL `http://127.0.0.1:3000/dashboard.html`, title `Dashboard`. |
| CDP listener | `ss -ltnpe 'sport = :9222'` showed `127.0.0.1:9222` listening, UID 1000, socket inode 269694251, but no process owner. |
| Listener owner lookup | `lsof -nP -iTCP:9222 -sTCP:LISTEN` returned no rows. Scanning visible `/proc/*/fd` entries found no owner for the listener inode. |
| SSH process view | The Agent Host process list showed multiple `sshd-session` processes (interactive and non-interactive). No Browser Host `ssh` client process was present on the Agent Host. |
| Tunnel isolation attempt | `sudo -n ss -ltnpe 'sport = :9222'` was denied by the tool policy before the command ran. |

## Cutover safety decision

The initial Agent Host-side attempt could not map the evaluation tunnel to a unique, safely stoppable process. Multiple SSH sessions were active, and the Browser Host-side SSH client was not present on this host. No SSH process was terminated from the Agent Host. The user then stopped the evaluation tunnel from the Browser Host's dedicated terminal.

## POST-CUTOVER — connection evidence

After the user-side stop, Agent Host connection checks showed:

| Check | Result |
|---|---|
| CDP endpoint `http://127.0.0.1:9222/json/version` | `curl` failed with exit 7: `Could not connect to server` (failure reported after 0 ms). |
| Buggy app `http://127.0.0.1:3000/api/config` | HTTP 200; body `{"settingsSaveFails":true,"dashboardThrows":true}`. The app remained reachable. |
| Chrome DevTools MCP `list_pages` | Failed: `Could not connect to Chrome. Check if Chrome is running. Cause: Failed to fetch browser webSocket URL from http://127.0.0.1:9222/json/version: fetch failed` |

The MCP error corresponds to the unreachable configured CDP endpoint. No other endpoint was tried.

## Browser-debug-agent Skill result

The `browser-debug-agent` workflow was executed against the post-cutover state. Its PRECHECK fails closed because Chrome/CDP is unavailable; the Skill outcome for this run is **`NOT_VERIFIED`**. A browser reproduction/observation cannot proceed without the browser connection.

| Evidence category after cutover | Status |
|---|---|
| Console | NOT_COLLECTED — no Chrome page connection |
| Network | NOT_COLLECTED — no Chrome page connection |
| DOM/runtime | NOT_COLLECTED — no Chrome page connection |
| Screenshot | NOT_COLLECTED — no Chrome page connection |
| Browser evidence | Unavailable; no substitute browser used |

- Fallback: none. No Playwright, local browser, alternate CDP endpoint, or other browser was used.
- `VERIFIED` / `FIX_VERIFIED`: not reported.
- Agent Host SSH processes: none were terminated by the agent.

The fail-closed result is supported by the MCP connection error and unavailable browser evidence. It does not claim the application UI was verified while the tunnel was down.
